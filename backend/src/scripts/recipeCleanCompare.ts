import 'dotenv/config';
/**
 * Controlled before/after eval for the cleanup pass over the real corpus.
 *
 * For each URL: scrape ONCE -> score the raw draft -> run the Gemini cleanup
 * on that same draft -> score the cleaned draft. Because both scores come
 * from the SAME fetch, this eliminates the flaky-bot-wall URL-drift confound
 * you get by toggling RECIPE_CLEANUP_ENABLED across two separate corpus runs.
 *
 * Reports per-URL raw->cleaned deltas, mean lift, regression count, and the
 * net defect resolved/introduced tallies. Writes the full run to
 * artifacts/recipe-quality/compare-<ts>.json.
 *
 * Usage: npm run recipe:clean-compare [N]      (N = first N URLs; default all)
 * Requires GEMINI_API_KEY.
 */

import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { importRawRecipeDraftForEval } from '../services/recipeImportService.js';
import { cleanupRecipeDraft } from '../services/recipeCleanupService.js';
import { scoreRecipeDraft } from '../services/recipeQualityScore.js';
import { RECIPE_URL_CORPUS, type CorpusEntry } from './fixtures/recipeUrlCorpus.js';

const PER_URL_TIMEOUT_MS = 55_000;
const CONCURRENCY = 4;

interface CompareRow {
  url: string;
  source: string;
  category: string;
  ok: boolean;
  errorCode?: string;
  rawScore?: number;
  cleanedScore?: number;
  delta?: number;
  changed?: boolean;
  resolved?: string[];
  introduced?: string[];
}

function timeout<T>(p: Promise<T>, ms: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('HARNESS_TIMEOUT')), ms);
    p.then((v) => { clearTimeout(t); resolve(v); }, (e) => { clearTimeout(t); reject(e); });
  });
}

function errorCodeOf(err: unknown): string {
  if (err && typeof err === 'object') {
    const code = (err as { code?: unknown }).code;
    if (typeof code === 'string') return code;
    const m = (err as { message?: unknown }).message;
    if (typeof m === 'string') return m.slice(0, 50);
  }
  return String(err).slice(0, 50);
}

async function runOne(entry: CorpusEntry): Promise<CompareRow> {
  try {
    const raw = await timeout(importRawRecipeDraftForEval(entry.url), PER_URL_TIMEOUT_MS);
    const rawReport = scoreRecipeDraft(raw);
    const { cleaned, changed } = await timeout(cleanupRecipeDraft(raw), PER_URL_TIMEOUT_MS);
    const cleanedReport = scoreRecipeDraft(cleaned);

    const beforeCodes = new Set(rawReport.defects.map((d) => d.code));
    const afterCodes = new Set(cleanedReport.defects.map((d) => d.code));
    return {
      url: entry.url, source: entry.source, category: entry.category, ok: true,
      rawScore: rawReport.overall, cleanedScore: cleanedReport.overall,
      delta: cleanedReport.overall - rawReport.overall, changed,
      resolved: [...beforeCodes].filter((c) => !afterCodes.has(c)),
      introduced: [...afterCodes].filter((c) => !beforeCodes.has(c)),
    };
  } catch (err) {
    return { url: entry.url, source: entry.source, category: entry.category, ok: false, errorCode: errorCodeOf(err) };
  }
}

async function runPool(entries: CorpusEntry[]): Promise<CompareRow[]> {
  const out: CompareRow[] = new Array(entries.length);
  let next = 0;
  async function worker() {
    while (next < entries.length) {
      const idx = next++;
      const row = await runOne(entries[idx]);
      out[idx] = row;
      if (row.ok) {
        const d = row.delta!;
        const arrow = d > 0 ? '▲' : d < 0 ? '▼' : '=';
        console.log(`  ${String(row.rawScore).padStart(3)} → ${String(row.cleanedScore).padStart(3)}  ${arrow}${String(Math.abs(d)).padStart(3)} | ${row.source.padEnd(20)} | resolved: ${(row.resolved ?? []).join(', ').slice(0, 36)}`);
        if (row.introduced?.length) console.log(`                          ⚠ introduced: ${row.introduced.join(', ')}`);
      } else {
        console.log(`  FAILED   ${(row.errorCode ?? '').padEnd(28)} | ${row.source}`);
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, entries.length) }, () => worker()));
  return out;
}

function mean(ns: number[]): number { return ns.length ? ns.reduce((a, b) => a + b, 0) / ns.length : 0; }

async function main() {
  const args = process.argv.slice(2);
  const entries = args[0] && /^\d+$/.test(args[0]) ? RECIPE_URL_CORPUS.slice(0, Number(args[0])) : RECIPE_URL_CORPUS;

  console.log(`Controlled raw→cleaned compare over ${entries.length} URL(s)…\n`);
  console.log('  RAW → CLN   Δ   | SOURCE               | RESOLVED DEFECTS');
  console.log('  ' + '─'.repeat(82));

  const started = Date.now();
  const rows = await runPool(entries);
  const ok = rows.filter((r) => r.ok);

  console.log('\n──────────── CONTROLLED SUMMARY ────────────');
  console.log(`Compared (raw + cleaned on same scrape): ${ok.length}`);
  if (ok.length) {
    const rawMean = Math.round(mean(ok.map((r) => r.rawScore!)));
    const cleanMean = Math.round(mean(ok.map((r) => r.cleanedScore!)));
    const deltas = ok.map((r) => r.delta!);
    const improved = deltas.filter((d) => d > 0).length;
    const regressed = deltas.filter((d) => d < 0).length;
    const flat = deltas.filter((d) => d === 0).length;

    console.log(`Mean RAW score:     ${rawMean}`);
    console.log(`Mean CLEANED score: ${cleanMean}`);
    console.log(`Mean delta:         ${mean(deltas) >= 0 ? '+' : ''}${mean(deltas).toFixed(1)}`);
    console.log(`Per-URL:            ${improved} improved · ${flat} flat · ${regressed} regressed`);

    const resolvedCounts = new Map<string, number>();
    const introducedCounts = new Map<string, number>();
    for (const r of ok) {
      for (const c of r.resolved ?? []) resolvedCounts.set(c, (resolvedCounts.get(c) ?? 0) + 1);
      for (const c of r.introduced ?? []) introducedCounts.set(c, (introducedCounts.get(c) ?? 0) + 1);
    }
    console.log('\nDefects RESOLVED by cleanup (count of recipes):');
    for (const [c, n] of [...resolvedCounts.entries()].sort((a, b) => b[1] - a[1])) console.log(`  ${String(n).padStart(3)}  ${c}`);
    if (introducedCounts.size) {
      console.log('\nDefects INTRODUCED by cleanup (watch list):');
      for (const [c, n] of [...introducedCounts.entries()].sort((a, b) => b[1] - a[1])) console.log(`  ${String(n).padStart(3)}  ${c}`);
    }
  }

  const outDir = join(process.cwd(), 'artifacts', 'recipe-quality');
  mkdirSync(outDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const outPath = join(outDir, `compare-${stamp}.json`);
  writeFileSync(outPath, JSON.stringify({ startedAt: started, durationMs: Date.now() - started, rows }, null, 2));
  console.log(`\nFull comparison written to ${outPath}`);
}

main().catch((err) => { console.error('Compare crashed:', err); process.exit(1); });
