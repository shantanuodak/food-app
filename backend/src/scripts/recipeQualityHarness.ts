/**
 * Recipe parse-quality harness.
 *
 * Imports each URL in the corpus through the REAL import pipeline
 * (importRecipeDraftForSmokeTest — no DB writes), scores the resulting
 * draft with scoreRecipeDraft, and prints:
 *   - a per-recipe line (band, overall, import time, top defect codes)
 *   - import success rate (failures reported separately so dead/blocked
 *     URLs don't pollute the quality distribution)
 *   - band distribution + mean/median overall over successful imports
 *   - mean per-dimension scores
 *   - the defect leaderboard (most frequent defect codes) — this is what
 *     tells us WHAT to fix in the parser, ranked by prevalence
 *   - a per-category breakdown (blogs vs media vs institutional…)
 * and writes the full run to artifacts/recipe-quality/<timestamp>.json.
 *
 * Usage:
 *   npm run recipe:quality            # full corpus
 *   npm run recipe:quality -- 12      # first 12 URLs (quick signal)
 *   npm run recipe:quality -- url https://...   # a single ad-hoc URL
 *
 * SOCIAL LANE (TikTok/IG/FB) is NOT covered here — those import via audio
 * transcription, not URL scraping. A separate transcript-fixture harness is
 * needed for that; flagged in the corpus file.
 */

import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { importRecipeDraftForSmokeTest } from '../services/recipeImportService.js';
import { scoreRecipeDraft, type RecipeQualityReport } from '../services/recipeQualityScore.js';
import { RECIPE_URL_CORPUS, type CorpusEntry } from './fixtures/recipeUrlCorpus.js';

const PER_URL_TIMEOUT_MS = 35_000;
const CONCURRENCY = 4;

interface RunResult {
  url: string;
  source: string;
  category: string;
  ok: boolean;
  errorCode?: string;
  importMs: number;
  report?: RecipeQualityReport;
}

function timeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('HARNESS_TIMEOUT')), ms);
    promise.then(
      (v) => { clearTimeout(t); resolve(v); },
      (e) => { clearTimeout(t); reject(e); },
    );
  });
}

function errorCodeOf(err: unknown): string {
  if (err && typeof err === 'object') {
    const code = (err as { code?: unknown }).code;
    if (typeof code === 'string') return code;
    const message = (err as { message?: unknown }).message;
    if (typeof message === 'string') return message.slice(0, 60);
  }
  return String(err).slice(0, 60);
}

async function runOne(entry: CorpusEntry): Promise<RunResult> {
  const start = Date.now();
  try {
    const draft = await timeout(importRecipeDraftForSmokeTest(entry.url), PER_URL_TIMEOUT_MS);
    const report = scoreRecipeDraft(draft);
    return { url: entry.url, source: entry.source, category: entry.category, ok: true, importMs: Date.now() - start, report };
  } catch (err) {
    return { url: entry.url, source: entry.source, category: entry.category, ok: false, errorCode: errorCodeOf(err), importMs: Date.now() - start };
  }
}

async function runPool(entries: CorpusEntry[]): Promise<RunResult[]> {
  const results: RunResult[] = new Array(entries.length);
  let next = 0;
  async function worker() {
    while (next < entries.length) {
      const idx = next++;
      const entry = entries[idx];
      const result = await runOne(entry);
      results[idx] = result;
      const tag = result.ok
        ? `${result.report!.band.toUpperCase().padEnd(9)} ${String(result.report!.overall).padStart(3)}`
        : `FAILED    ${(result.errorCode ?? '').padEnd(28)}`;
      const top = result.ok
        ? result.report!.defects.slice(0, 3).map((d) => d.code).join(', ')
        : '';
      console.log(`  ${tag} | ${`${result.importMs}ms`.padStart(7)} | ${result.source.padEnd(20)} | ${top}`);
    }
  }
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, entries.length) }, () => worker()));
  return results;
}

function median(nums: number[]): number {
  if (nums.length === 0) return 0;
  const sorted = [...nums].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : Math.round((sorted[mid - 1] + sorted[mid]) / 2);
}

function summarize(results: RunResult[]): void {
  const ok = results.filter((r) => r.ok && r.report);
  const failed = results.filter((r) => !r.ok);

  console.log('\n──────────── SUMMARY ────────────');
  console.log(`Total URLs:        ${results.length}`);
  console.log(`Imported OK:       ${ok.length} (${Math.round((ok.length / results.length) * 100)}%)`);
  console.log(`Import failures:   ${failed.length}`);

  if (failed.length) {
    const byCode = new Map<string, number>();
    for (const f of failed) byCode.set(f.errorCode ?? '?', (byCode.get(f.errorCode ?? '?') ?? 0) + 1);
    console.log('  failure codes:');
    for (const [code, count] of [...byCode.entries()].sort((a, b) => b[1] - a[1])) {
      console.log(`    ${String(count).padStart(3)}  ${code}`);
    }
  }

  if (ok.length === 0) {
    console.log('\nNo successful imports to score.');
    return;
  }

  const overalls = ok.map((r) => r.report!.overall);
  const mean = Math.round(overalls.reduce((a, b) => a + b, 0) / overalls.length);
  console.log(`\nOverall score:     mean ${mean}  median ${median(overalls)}  min ${Math.min(...overalls)}  max ${Math.max(...overalls)}`);

  const bands = { excellent: 0, good: 0, fair: 0, poor: 0 };
  for (const r of ok) bands[r.report!.band] += 1;
  console.log(`Bands:             excellent ${bands.excellent} | good ${bands.good} | fair ${bands.fair} | poor ${bands.poor}`);

  // Mean per dimension.
  const dims = ['title', 'ingredientIntegrity', 'ingredientParseability', 'stepIntegrity', 'metadata', 'media', 'noiseFree'] as const;
  console.log('\nMean per-dimension (0..1):');
  for (const dim of dims) {
    const avg = ok.reduce((sum, r) => sum + r.report!.dimensions[dim], 0) / ok.length;
    const bar = '█'.repeat(Math.round(avg * 20)).padEnd(20, '░');
    console.log(`  ${dim.padEnd(24)} ${bar} ${avg.toFixed(2)}`);
  }

  // Defect leaderboard.
  const defectCounts = new Map<string, number>();
  for (const r of ok) {
    for (const d of r.report!.defects) defectCounts.set(d.code, (defectCounts.get(d.code) ?? 0) + 1);
  }
  console.log('\nDefect leaderboard (count of recipes affected):');
  for (const [code, count] of [...defectCounts.entries()].sort((a, b) => b[1] - a[1])) {
    console.log(`  ${String(count).padStart(3)}  ${code}`);
  }

  // Per-category mean.
  console.log('\nMean score by category:');
  const cats = [...new Set(ok.map((r) => r.category))];
  for (const cat of cats) {
    const rows = ok.filter((r) => r.category === cat);
    const avg = Math.round(rows.reduce((s, r) => s + r.report!.overall, 0) / rows.length);
    console.log(`  ${cat.padEnd(16)} ${String(avg).padStart(3)}  (n=${rows.length})`);
  }
}

async function main() {
  const args = process.argv.slice(2);
  let entries: CorpusEntry[] = RECIPE_URL_CORPUS;

  if (args[0] === 'url' && args[1]) {
    entries = [{ url: args[1], source: 'adhoc', category: 'aggregator' }];
  } else if (args[0] && /^\d+$/.test(args[0])) {
    entries = RECIPE_URL_CORPUS.slice(0, Number(args[0]));
  }

  console.log(`Running parse-quality harness over ${entries.length} URL(s), concurrency ${CONCURRENCY}…\n`);
  console.log('  BAND      SCR |   TIME  | SOURCE               | TOP DEFECTS');
  console.log('  ' + '─'.repeat(78));

  const started = Date.now();
  const results = await runPool(entries);
  summarize(results);

  // Persist full run.
  const outDir = join(process.cwd(), 'artifacts', 'recipe-quality');
  mkdirSync(outDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const outPath = join(outDir, `${stamp}.json`);
  writeFileSync(outPath, JSON.stringify({ startedAt: started, durationMs: Date.now() - started, results }, null, 2));
  console.log(`\nFull results written to ${outPath}`);
}

main().catch((err) => {
  console.error('Harness crashed:', err);
  process.exit(1);
});
