import { config } from '../config.js';
import { runPrimaryParsePipeline } from '../services/parsePipelineService.js';

function requireEnv(name: 'FATSECRET_CLIENT_ID' | 'FATSECRET_CLIENT_SECRET'): string {
  const value = process.env[name] || '';
  if (!value.trim()) {
    throw new Error(`Missing ${name}. Set it in backend .env before running this smoke test.`);
  }
  return value.trim();
}

async function main(): Promise<void> {
  requireEnv('FATSECRET_CLIENT_ID');
  requireEnv('FATSECRET_CLIENT_SECRET');

  const sample = process.argv.slice(2).join(' ').trim() || '2 eggs and toast';
  const cacheScope = process.env.FATSECRET_SMOKE_CACHE_SCOPE?.trim() || `fatsecret_smoke_${Date.now()}`;
  console.log('[fatsecret_smoke] config');
  console.log(
    JSON.stringify(
      {
        fatsecretEnabled: config.fatsecretEnabled,
        fatsecretRegion: config.fatsecretRegion,
        fatsecretLanguage: config.fatsecretLanguage || null,
        fatsecretMinCoverage: config.fatsecretMinCoverage,
        fatsecretMinConfidence: config.fatsecretMinConfidence,
        parseCacheMinConfidence: config.parseCacheMinConfidence,
        cacheScope,
        geminiEnabled: Boolean(config.geminiApiKey)
      },
      null,
      2
    )
  );

  console.log(`[fatsecret_smoke] parsing: "${sample}"`);
  const output = await runPrimaryParsePipeline(sample, { allowFallback: true, cacheScope });

  console.log('[fatsecret_smoke] result');
  console.log(
    JSON.stringify(
      {
        route: output.route,
        cacheHit: output.cacheHit,
        fallbackUsed: output.fallbackUsed,
        fallbackModel: output.fallbackModel,
        needsClarification: output.needsClarification,
        clarificationQuestions: output.clarificationQuestions,
        confidence: output.result.confidence,
        totals: output.result.totals,
        items: output.result.items.map((item) => ({
          name: item.name,
          quantity: item.quantity,
          unit: item.unit,
          grams: item.grams,
          calories: item.calories,
          protein: item.protein,
          carbs: item.carbs,
          fat: item.fat,
          nutritionSourceId: item.nutritionSourceId,
          matchConfidence: item.matchConfidence
        })),
        assumptions: output.result.assumptions
      },
      null,
      2
    )
  );

  if (output.route !== 'fatsecret') {
    console.warn(
      `[fatsecret_smoke] route is "${output.route}", not "fatsecret". Check FATSECRET_* creds, gating, and confidence thresholds.`
    );
  } else {
    console.log('[fatsecret_smoke] success: route=fatsecret');
  }
}

main().catch((err) => {
  console.error('[fatsecret_smoke] failed', err instanceof Error ? err.message : err);
  process.exitCode = 1;
});
