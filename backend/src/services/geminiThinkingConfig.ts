/**
 * Helper for translating user-facing thinking-level strings to Gemini API
 * `thinkingConfig.thinkingBudget` integers. Kept in a separate module from
 * `geminiFlashClient` so that test mocks of the client do not accidentally
 * shadow this helper to `undefined`.
 *
 * Per https://ai.google.dev/api/generate-content#thinkingconfig the
 * thinkingBudget is an integer:
 *   0          -> thinking disabled
 *   positive   -> token budget cap
 *   -1         -> dynamic (model decides)
 *
 * Mapping:
 *   off | none | disabled   -> 0
 *   low                     -> 256
 *   medium                  -> 1024
 *   high                    -> 4096
 *   auto | default | ""     -> undefined  (omit thinkingConfig; model decides)
 *   "<int>"                 -> parsed integer
 */
export function resolveThinkingBudget(level: string | undefined): number | undefined {
  if (!level) return undefined;
  const normalized = String(level).trim().toLowerCase();
  if (!normalized || normalized === 'auto' || normalized === 'default') return undefined;
  if (normalized === 'off' || normalized === 'none' || normalized === 'disabled') return 0;
  if (normalized === 'low') return 256;
  if (normalized === 'medium') return 1024;
  if (normalized === 'high') return 4096;
  const parsed = Number.parseInt(normalized, 10);
  return Number.isFinite(parsed) ? Math.max(0, parsed) : undefined;
}
