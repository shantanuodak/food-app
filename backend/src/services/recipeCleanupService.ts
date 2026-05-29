import { config } from '../config.js';
import { generateGeminiJson } from './geminiFlashClient.js';
import type { RecipeDraft, RecipeIngredientDraft, RecipeStepDraft } from './recipeImportService.js';

/**
 * LLM structuring + cleanup pass for imported recipes.
 *
 * The deterministic scrape/reader pipeline produces a RecipeDraft where:
 *  - ingredients are a single rawText blob each (quantity/unit/name never set)
 *  - steps can be one giant prose blob, or carry nav/ad/social junk lines
 *  - the title can carry a site suffix, clickbait punctuation, emoji/hashtags
 *
 * This pass hands the messy fields to Gemini and asks for a cleaned,
 * STRUCTURED version: ingredients split into quantity/unit/name, steps split
 * into discrete actions, junk dropped, title tidied. It is intentionally
 * conservative — the prompt forbids inventing content; everything that isn't
 * clearly removable is preserved. Non-text fields (image, times, servings,
 * source) pass through untouched.
 *
 * The Gemini call is injected (see `deps`) so unit tests can exercise the
 * full mapping deterministically with a canned response and no network.
 */

// MARK: - Types

export interface RecipeCleanupResult {
  cleaned: RecipeDraft;
  /** True if the LLM pass ran and produced a usable result that was applied. */
  changed: boolean;
  /** Set when the pass was skipped/failed; the original draft is returned as-is. */
  skippedReason?: 'llm_unavailable' | 'llm_empty' | 'llm_parse_error' | 'llm_unusable';
  usage?: { model: string; inputTokens: number; outputTokens: number };
}

interface LlmCleanIngredient {
  quantity?: string | null;
  unit?: string | null;
  name?: string | null;
  raw?: string | null;
}

interface LlmCleanResponse {
  title?: string | null;
  description?: string | null;
  ingredients?: LlmCleanIngredient[];
  steps?: string[];
}

type GenerateFn = (opts: { model: string; prompt: string; temperature?: number; maxOutputTokens?: number; timeoutMs?: number }) =>
  Promise<{ jsonText: string; usage: { model: string; inputTokens: number; outputTokens: number } } | null>;

export interface RecipeCleanupDeps {
  generate?: GenerateFn;
  model?: string;
}

// MARK: - Prompt

function buildPrompt(draft: RecipeDraft): string {
  // Feed the model ONLY the messy text fields. Number the lines so it can
  // map cleanly and so we can see what it dropped.
  const ingredientLines = draft.ingredients.map((i, idx) => `${idx + 1}. ${i.rawText}`).join('\n');
  const stepLines = draft.steps.map((s, idx) => `${idx + 1}. ${s.text}`).join('\n') || '(none provided)';

  return [
    'You clean up scraped recipe data into structured, human-readable JSON.',
    'You are given a recipe scraped from a web page. It may contain noise:',
    'navigation text, ads, "Jump to Recipe", nutrition-fact lines, blog prose,',
    'social calls-to-action (subscribe/follow), hashtags, emoji, or URLs.',
    '',
    'RULES — follow exactly:',
    '1. DO NOT invent ingredients, steps, quantities, or facts. Only restructure',
    '   and clean what is present. If unsure whether a line is an ingredient,',
    '   keep it.',
    '2. For each real ingredient, split it into quantity, unit, and name:',
    '   - quantity: the amount as written ("2", "1 1/2", "1-2"), or null if none',
    '   - unit: the measurement unit ("cup", "tbsp", "g", "clove"), or null',
    '   - name: the ingredient itself plus prep notes ("flour", "garlic, minced")',
    '   - raw: a clean human-readable version of the whole line',
    '   Preserve quantities EXACTLY as written. Do not convert units.',
    '3. DROP lines that are not ingredients: nutrition facts (calories/protein/',
    '   fat/etc.), nav/ads, "Jump to Recipe", "Print", "Scale", URLs, headings.',
    '4. Split instructions into discrete, ordered steps — one concrete cooking',
    '   action per step. If the input crams all steps into one paragraph, break',
    '   it apart. Every step MUST be an action that starts with a verb (Heat,',
    '   Add, Stir, Bake...). DO NOT emit non-actions as steps: section headings',
    '   ("For the sauce:"), sign-offs ("Enjoy!", "Serve and enjoy"), social CTAs',
    '   ("like and subscribe"), nav, ads, URLs, or hashtags. Fold a heading into',
    '   the step that follows it rather than emitting it on its own.',
    '5. Clean the title: remove trailing site names ("... | Site"), clickbait',
    '   ("The BEST Ever!!"), emoji, and hashtags. Keep the dish name.',
    '6. Keep the description to one clean sentence, or null if it is just blog prose.',
    '',
    'Return ONLY this JSON (no markdown fences):',
    '{',
    '  "title": string,',
    '  "description": string | null,',
    '  "ingredients": [{ "quantity": string|null, "unit": string|null, "name": string, "raw": string }],',
    '  "steps": [string]',
    '}',
    '',
    `TITLE: ${draft.title}`,
    `DESCRIPTION: ${draft.description ?? '(none)'}`,
    '',
    'INGREDIENTS:',
    ingredientLines,
    '',
    'INSTRUCTIONS:',
    stepLines,
  ].join('\n');
}

// MARK: - Mapping

function nonEmpty(value: string | null | undefined, max: number): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, max);
}

function mapResponseToDraft(draft: RecipeDraft, parsed: LlmCleanResponse): RecipeDraft | null {
  const ingredients: RecipeIngredientDraft[] = (parsed.ingredients ?? [])
    .map((item): RecipeIngredientDraft | null => {
      const name = nonEmpty(item.name, 220);
      const raw = nonEmpty(item.raw, 700) ?? name;
      if (!raw) return null;
      return {
        rawText: raw,
        quantityText: nonEmpty(item.quantity ?? null, 120),
        unitText: nonEmpty(item.unit ?? null, 80),
        ingredientName: name,
      };
    })
    .filter((x): x is RecipeIngredientDraft => x !== null);

  // Guardrail: never let the LLM empty out a recipe that had ingredients.
  // If it returned nothing usable, treat the pass as unusable and keep raw.
  if (ingredients.length === 0) return null;

  const steps: RecipeStepDraft[] = (parsed.steps ?? [])
    .map((text) => nonEmpty(text, 2000))
    .filter((x): x is string => x !== null)
    .map((text) => ({ text }));

  const title = nonEmpty(parsed.title, 180) ?? draft.title;

  return {
    ...draft,
    title,
    description: nonEmpty(parsed.description ?? null, 2000) ?? draft.description,
    ingredients,
    // If the model returned no steps but the original had some, keep the
    // originals rather than dropping instructions entirely.
    steps: steps.length > 0 ? steps : draft.steps,
  };
}

function parseJsonLoose(jsonText: string): LlmCleanResponse | null {
  // Strip accidental markdown fences, then parse.
  const cleaned = jsonText.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '');
  try {
    return JSON.parse(cleaned) as LlmCleanResponse;
  } catch {
    // Last resort: grab the outermost {...}.
    const start = cleaned.indexOf('{');
    const end = cleaned.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(cleaned.slice(start, end + 1)) as LlmCleanResponse;
      } catch {
        return null;
      }
    }
    return null;
  }
}

// MARK: - Entry point

export async function cleanupRecipeDraft(
  draft: RecipeDraft,
  deps: RecipeCleanupDeps = {}
): Promise<RecipeCleanupResult> {
  const generate: GenerateFn = deps.generate ?? generateGeminiJson;
  const model = deps.model ?? config.geminiFlashModel;

  const result = await generate({
    model,
    prompt: buildPrompt(draft),
    temperature: 0.1,
    maxOutputTokens: 4000,
    timeoutMs: config.geminiTimeoutMs,
  });

  if (!result) {
    return { cleaned: draft, changed: false, skippedReason: 'llm_unavailable' };
  }
  if (!result.jsonText?.trim()) {
    return { cleaned: draft, changed: false, skippedReason: 'llm_empty', usage: result.usage };
  }

  const parsed = parseJsonLoose(result.jsonText);
  if (!parsed) {
    return { cleaned: draft, changed: false, skippedReason: 'llm_parse_error', usage: result.usage };
  }

  const mapped = mapResponseToDraft(draft, parsed);
  if (!mapped) {
    return { cleaned: draft, changed: false, skippedReason: 'llm_unusable', usage: result.usage };
  }

  return { cleaned: mapped, changed: true, usage: result.usage };
}
