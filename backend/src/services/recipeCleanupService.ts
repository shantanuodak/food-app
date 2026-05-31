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
  servings?: string | null;
  prepTime?: string | null;
  cookTime?: string | null;
  totalTime?: string | null;
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
    '7. Extract servings and times ONLY if the text states them explicitly',
    '   ("serves 4" -> servings "4"; "bake for 35 minutes" -> cookTime',
    '   "35 minutes"; "ready in 30 min" -> totalTime). If a value is not',
    '   clearly stated, return null. NEVER guess or estimate a time/serving.',
    '',
    'Return ONLY this JSON (no markdown fences):',
    '{',
    '  "title": string,',
    '  "description": string | null,',
    '  "servings": string | null,',
    '  "prepTime": string | null,',
    '  "cookTime": string | null,',
    '  "totalTime": string | null,',
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

  // Guardrail #2: the cleanup pass is meant to de-noise and split lines, not
  // remove content. Dropping obvious junk (a "Jump to Recipe"/nutrition line)
  // and merging a quantity-only line into the next legitimately shrink the
  // count — typically by up to a third. A drop past HALF means the model
  // discarded real ingredients, so treat the pass as unusable and keep the raw
  // draft. (Threshold kept at 50%, not higher, so normal junk removal — e.g.
  // the 6→4 de-noise case — clears it with margin.)
  const rawIngredientCount = draft.ingredients.length;
  if (rawIngredientCount > 0 && ingredients.length < Math.ceil(rawIngredientCount * 0.5)) {
    return null;
  }

  const steps: RecipeStepDraft[] = (parsed.steps ?? [])
    .map((text) => nonEmpty(text, 2000))
    .filter((x): x is string => x !== null)
    .map((text) => ({ text }));

  const title = nonEmpty(parsed.title, 180) ?? draft.title;

  return {
    ...draft,
    title,
    description: nonEmpty(parsed.description ?? null, 2000) ?? draft.description,
    // Metadata: PREFER the existing scraped value (JSON-LD is authoritative);
    // only fall back to the LLM-extracted value when the draft lacks one.
    // This fills the gap for social/reader-fallback drafts (which have no
    // metadata) while never overwriting a good scraped value with a guess.
    servings: draft.servings ?? nonEmpty(parsed.servings ?? null, 120),
    prepTime: draft.prepTime ?? nonEmpty(parsed.prepTime ?? null, 120),
    cookTime: draft.cookTime ?? nonEmpty(parsed.cookTime ?? null, 120),
    totalTime: draft.totalTime ?? nonEmpty(parsed.totalTime ?? null, 120),
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

// MARK: - Raw-text extraction (social captions / shared text)
//
// The social/browser lane gets a full post CAPTION (or pasted recipe text),
// not a pre-extracted ingredient list. Running the heuristic extractor first
// and THEN cleanup is lossy: the heuristic only keeps quantity-bearing lines,
// so caption ingredients with no quantity ("Tomato", "Cucumber", "Red onion")
// are dropped and the dish-name title is mangled BEFORE Gemini ever sees them.
//
// This pass instead hands Gemini the ENTIRE raw caption and asks it to extract
// the recipe from scratch: real dish-name title, ALL ingredients (including
// quantity-less ones), and ordered steps — dropping social noise (macros,
// hashtags, "SAVE THIS", follow CTAs). There is no pre-extracted baseline, so
// the 50%-drop guardrail used by cleanupRecipeDraft does not apply here.

function buildExtractionPrompt(rawText: string): string {
  return [
    'You extract a single structured recipe from raw text that a user imported',
    'from a social post (Instagram / TikTok / Facebook caption) or pasted in.',
    'The text is messy: it may open with hooks ("SAVE THIS", "I lost 40lbs"),',
    'macro/nutrition lines, section headers ("For the chicken:", "Salad:"),',
    'emoji, hashtags, and follow/subscribe calls-to-action.',
    '',
    'RULES — follow exactly:',
    '1. DO NOT invent ingredients, steps, quantities, or facts. Extract only what',
    '   is present. Do not convert units or change quantities.',
    '2. Extract EVERY ingredient, INCLUDING ones with no quantity (e.g. "Tomato",',
    '   "Cucumber", "Salt to taste"). A line under an ingredient/salad/sauce',
    '   heading is an ingredient even if it has no number. Split each into:',
    '   - quantity: amount as written ("1", "1 1/2", "24"), or null',
    '   - unit: measurement unit ("cup", "tsp", "tbsp", "oz", "clove"), or null',
    '   - name: the ingredient plus prep notes ("chicken breast, thinly sliced",',
    '     "red onion, chopped")',
    '   - raw: a clean human-readable version of the whole line',
    '3. DROP non-ingredient noise: macro/nutrition lines (calories/protein/carbs/',
    '   fat), hooks, hashtags, emoji-only lines, "SAVE THIS", follow/subscribe',
    '   CTAs, and pure section headers (fold the header meaning into the names',
    '   below it; do not emit the header itself as an ingredient).',
    '4. Extract instructions as discrete, ordered steps, one action per step,',
    '   each starting with a verb (Sear, Add, Let, Drizzle, Combine...). If the',
    '   text crams steps into one sentence, split them. Do NOT emit headings,',
    '   sign-offs, or CTAs as steps. If there are genuinely no instructions,',
    '   return an empty steps array.',
    '5. title: the dish name (e.g. "Mediterranean Bowl", "Street Corn Chicken',
    '   Bowl"). Derive it from the hook/caption if needed ("I lost 40lbs eating',
    '   THIS Mediterranean bowl" -> "Mediterranean Bowl"). NEVER use an',
    '   ingredient or a section header ("For the chicken:") as the title.',
    '6. description: one clean sentence if the caption has a real one, else null.',
    '7. servings/times: extract ONLY if explicitly stated ("makes 3" -> servings',
    '   "3"; "sear 3-5 mins per side"); otherwise null. Never guess.',
    '',
    'Return ONLY this JSON (no markdown fences):',
    '{',
    '  "title": string,',
    '  "description": string | null,',
    '  "servings": string | null,',
    '  "prepTime": string | null,',
    '  "cookTime": string | null,',
    '  "totalTime": string | null,',
    '  "ingredients": [{ "quantity": string|null, "unit": string|null, "name": string, "raw": string }],',
    '  "steps": [string]',
    '}',
    '',
    'RAW TEXT:',
    rawText,
  ].join('\n');
}

/**
 * Extract a structured recipe from a raw caption / pasted text via Gemini.
 * Unlike cleanupRecipeDraft (which de-noises a PRE-EXTRACTED draft), this reads
 * the whole text and builds the ingredient/step lists from scratch — the right
 * tool for social captions. Returns null on any LLM failure / empty / no
 * ingredients, so the caller can fall back to the heuristic builder.
 */
export async function extractRecipeFromText(
  rawText: string,
  base: RecipeDraft,
  deps: RecipeCleanupDeps = {}
): Promise<RecipeDraft | null> {
  const text = rawText?.trim();
  if (!text) return null;

  const generate: GenerateFn = deps.generate ?? generateGeminiJson;
  const model = deps.model ?? config.geminiFlashModel;

  const result = await generate({
    model,
    prompt: buildExtractionPrompt(text.slice(0, 8000)),
    temperature: 0.1,
    maxOutputTokens: 4000,
    timeoutMs: config.geminiTimeoutMs,
  });
  if (!result?.jsonText?.trim()) return null;

  const parsed = parseJsonLoose(result.jsonText);
  if (!parsed) return null;

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

  // No pre-extracted baseline here, so the only guardrail is: it must have
  // found at least one ingredient. Otherwise the extraction is unusable.
  if (ingredients.length === 0) return null;

  const steps: RecipeStepDraft[] = (parsed.steps ?? [])
    .map((stepText) => nonEmpty(stepText, 2000))
    .filter((x): x is string => x !== null)
    .map((stepText) => ({ text: stepText }));

  return {
    ...base,
    title: nonEmpty(parsed.title, 180) ?? base.title,
    description: nonEmpty(parsed.description ?? null, 2000) ?? base.description,
    servings: nonEmpty(parsed.servings ?? null, 120) ?? base.servings,
    prepTime: nonEmpty(parsed.prepTime ?? null, 120) ?? base.prepTime,
    cookTime: nonEmpty(parsed.cookTime ?? null, 120) ?? base.cookTime,
    totalTime: nonEmpty(parsed.totalTime ?? null, 120) ?? base.totalTime,
    ingredients,
    steps,
    // Extraction read the whole caption, so we trust it more than the heuristic.
    confidence: Math.max(base.confidence, 0.7),
  };
}
