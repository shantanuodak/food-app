import type { ParseResult } from './deterministicParser.js';
import { postProcessFoodImageResult } from './foodImagePostprocessService.js';

/**
 * Conservative text parse cleanup.
 *
 * This intentionally reuses the same product/compound guardrails as image
 * parsing, but disables broad alias merging. If a user explicitly types
 * "methi paratha, thepla", those should remain two rows. If Gemini splits
 * "mango chutney" into "Mango" + "Chutney" or splits a product flavor into
 * ingredients, we still repair that before the app displays/saves it.
 */
export function postProcessFoodTextResult(text: string, result: ParseResult): ParseResult {
  return postProcessFoodImageResult(result, {
    extractedText: text,
    assumptions: result.assumptions,
    mergeAliasDuplicates: false
  });
}
