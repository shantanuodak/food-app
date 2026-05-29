import type { RecipeDraft, RecipeIngredientDraft, RecipeStepDraft } from './recipeImportService.js';

/**
 * Recipe quality scoring — "how cleanly would a human read this recipe?"
 *
 * The import pipeline is deterministic (recipe-scraper / markdown reader /
 * audio transcript) and emits a RecipeDraft. Today the only "confidence"
 * signal is a fake binary (0.92 if steps exist else 0.78) that measures
 * nothing about actual quality. This module replaces that with a real,
 * dimension-by-dimension readability score plus a list of concrete defects
 * so we can (a) gate how a recipe is shown and (b) measure parse changes.
 *
 * Design goals:
 *  - PURE + deterministic: no network, no DB, no clock. Trivially testable,
 *    and runnable over a large URL corpus to get a defect distribution.
 *  - ACTIONABLE: the number alone is useless. Every point deducted comes
 *    with a Defect that names what's wrong, where, and how bad — that's
 *    what drives parser fixes and UI gating.
 *  - HUMAN-CENTERED: scores what a person scanning the recipe cares about —
 *    a clean title, ingredient lines that read as "qty unit item", real
 *    cooking steps in order, the times/servings they need, and the ABSENCE
 *    of blog/ad/social cruft.
 *
 * The overall score is a weighted sum of seven 0..1 dimensions, scaled to
 * 0..100. Weights live in DIMENSION_WEIGHTS and sum to 100 so a dimension's
 * weight IS its max point contribution.
 */

// MARK: - Public types

export type QualityDimension =
  | 'title'
  | 'ingredientIntegrity'
  | 'ingredientParseability'
  | 'stepIntegrity'
  | 'metadata'
  | 'media'
  | 'noiseFree';

export type DefectSeverity = 'low' | 'medium' | 'high';

export interface RecipeQualityDefect {
  dimension: QualityDimension;
  severity: DefectSeverity;
  /** Stable machine code for aggregation across a corpus (e.g. "step_prose_blob"). */
  code: string;
  /** Human-readable explanation of the specific problem. */
  message: string;
  /** Optional offending sample (truncated) so a reviewer can see it. */
  sample?: string;
}

export interface RecipeQualityReport {
  /** 0..100, weighted across dimensions. */
  overall: number;
  /** Coarse band derived from `overall` — drives UI gating decisions. */
  band: 'excellent' | 'good' | 'fair' | 'poor';
  /** Per-dimension 0..1 scores (before weighting). */
  dimensions: Record<QualityDimension, number>;
  defects: RecipeQualityDefect[];
}

// MARK: - Weights (sum to 100)

const DIMENSION_WEIGHTS: Record<QualityDimension, number> = {
  title: 12,
  ingredientIntegrity: 24,
  ingredientParseability: 12,
  stepIntegrity: 24,
  metadata: 10,
  media: 6,
  noiseFree: 12,
};

// MARK: - Lexicons

/**
 * Cooking verbs. A step that contains none of these (and isn't trivially
 * short) probably isn't a real instruction — it's blog prose, a heading,
 * or nav cruft. Kept deliberately broad to avoid false positives.
 */
const COOKING_VERBS = new Set([
  'add', 'arrange', 'bake', 'baste', 'beat', 'blend', 'boil', 'break', 'bring',
  'broil', 'brown', 'brush', 'chill', 'chop', 'coat', 'combine', 'cook', 'cool',
  'cover', 'cream', 'crush', 'cut', 'dice', 'dip', 'divide', 'drain', 'drizzle',
  'drop', 'dust', 'fill', 'flip', 'fold', 'fry', 'garnish', 'grate', 'grease',
  'grill', 'grind', 'heat', 'knead', 'layer', 'let', 'line', 'marinate', 'mash',
  'melt', 'microwave', 'mince', 'mix', 'pat', 'peel', 'place', 'poach', 'pour',
  'preheat', 'prepare', 'press', 'puree', 'reduce', 'refrigerate', 'remove',
  'repeat', 'return', 'rinse', 'roast', 'roll', 'rub', 'saute', 'sauté', 'scoop',
  'scrape', 'season', 'separate', 'serve', 'set', 'shake', 'simmer', 'slice',
  'soak', 'spoon', 'spread', 'sprinkle', 'steam', 'stir', 'strain', 'stuff',
  'taste', 'toast', 'top', 'toss', 'transfer', 'turn', 'use', 'wash', 'whisk',
  'whip', 'wrap',
]);

/**
 * Units we recognize for ingredient parseability. Singular + plural + common
 * abbreviations. Lowercased; the matcher lowercases input.
 */
const UNITS = new Set([
  'cup', 'cups', 'c', 'tbsp', 'tbsps', 'tablespoon', 'tablespoons', 'tbs',
  'tsp', 'tsps', 'teaspoon', 'teaspoons', 'g', 'gram', 'grams', 'kg',
  'kilogram', 'kilograms', 'oz', 'ounce', 'ounces', 'lb', 'lbs', 'pound',
  'pounds', 'ml', 'milliliter', 'milliliters', 'millilitre', 'millilitres',
  'l', 'liter', 'liters', 'litre', 'litres', 'pinch', 'pinches', 'dash',
  'dashes', 'clove', 'cloves', 'can', 'cans', 'slice', 'slices', 'stick',
  'sticks', 'package', 'packages', 'pkg', 'packet', 'packets', 'handful',
  'handfuls', 'sprig', 'sprigs', 'bunch', 'bunches', 'quart', 'quarts',
  'pint', 'pints', 'gallon', 'gallons', 'stalk', 'stalks', 'head', 'heads',
  'fillet', 'fillets', 'jar', 'jars', 'box', 'boxes', 'bottle', 'bottles',
]);

/**
 * Cruft phrases that should NEVER appear in a clean recipe. Blog/SEO/social
 * boilerplate, nav, ads, attribution. Matched case-insensitively as
 * substrings across all recipe text.
 */
const NOISE_PHRASES = [
  'jump to recipe', 'jump to the recipe', 'jump to video', 'skip to recipe',
  'print recipe', 'pin recipe', 'pin this', 'save recipe', 'rate this recipe',
  'leave a review', 'leave a comment', 'comment below', 'subscribe',
  'follow me', 'follow us', 'click here', 'read more', 'continue reading',
  'advertisement', 'sponsored', 'affiliate', 'shop this post', 'shop the post',
  'watch the video', 'scroll down', 'this post may contain', 'may contain affiliate',
  'as an amazon associate', 'all rights reserved', 'cook mode', 'prevent your screen',
  'get the recipe', 'see the recipe', 'recipe card below', 'tap here',
];

/**
 * Detects a nutrition-FACTS line ("Calories 320", "Protein 28g", "Sodium:
 * 400mg", "Nutrition Facts...") that leaked in as a fake ingredient.
 *
 * Critically, this must NOT fire on legitimate ingredients that merely
 * contain a nutrition word — "1 cup sugar", "2 tbsp brown sugar", "1 lb
 * ground beef", "1 scoop protein powder" are real ingredients, not junk.
 * So we require the nutrition word to be paired with a number+unit (the
 * shape of a facts panel), or an explicit "Nutrition Facts" / "Calories N".
 */
function looksLikeNutritionFact(text: string): boolean {
  if (/\bnutrition facts?\b/i.test(text)) return true;
  if (/\b(calories|kcal)\b/i.test(text) && /\d/.test(text)) return true;
  // "Protein 28g", "Sodium: 400 mg", "Total Fat 12g", "Sugars 9 g"
  if (/\b(protein|fat|carbohydrates?|carbs|sodium|fiber|fibre|cholesterol|sugars?)\b\s*:?\s*\d+\s*(g|mg|kcal|%)\b/i.test(text)) return true;
  return false;
}

// Emoji range (rough, covers the common pictographic blocks).
const EMOJI = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2190}-\u{21FF}\u{2B00}-\u{2BFF}]/u;

const HASHTAG = /(^|\s)#[\p{L}\p{N}_]+/u;
const MENTION = /(^|\s)@[\p{L}\p{N}_.]+/u;
const BARE_URL = /https?:\/\/\S+/i;

// Leading quantity: integer/decimal, mixed number, unicode vulgar fraction,
// "1/2", or a range like "2-3" / "2 to 3".
const LEADING_QUANTITY = /^\s*(\d+\s+\d\/\d|\d+\/\d|\d+([.,]\d+)?\s*(-|–|to)\s*\d+([.,]\d+)?|\d+([.,]\d+)?|[½⅓⅔¼¾⅕⅖⅗⅘⅙⅛⅜⅝⅞])/;

// MARK: - Helpers

function clamp01(value: number): number {
  if (Number.isNaN(value)) return 0;
  return Math.max(0, Math.min(1, value));
}

function truncate(text: string, max = 80): string {
  const t = text.trim();
  return t.length <= max ? t : `${t.slice(0, max - 1)}…`;
}

function tokenizeWords(text: string): string[] {
  return text.toLowerCase().split(/[^a-zà-ÿ]+/).filter(Boolean);
}

function firstCookingVerbWord(text: string): string | null {
  for (const word of tokenizeWords(text)) {
    if (COOKING_VERBS.has(word)) return word;
  }
  return null;
}

function looksParseableIngredient(raw: string): boolean {
  const text = raw.trim();
  if (!text) return false;
  if (LEADING_QUANTITY.test(text)) return true;
  // No leading quantity but contains a unit token early (e.g. "Salt, 1 tsp").
  const words = text.toLowerCase().replace(/[^a-z0-9/.\s]/g, ' ').split(/\s+/).filter(Boolean);
  return words.slice(0, 4).some((w) => UNITS.has(w));
}

function collectAllText(draft: RecipeDraft): string[] {
  const parts: string[] = [draft.title];
  if (draft.description) parts.push(draft.description);
  for (const ing of draft.ingredients) parts.push(ing.rawText);
  for (const step of draft.steps) parts.push(step.text);
  return parts.filter(Boolean);
}

// MARK: - Dimension scorers

function scoreTitle(draft: RecipeDraft, defects: RecipeQualityDefect[]): number {
  const title = draft.title?.trim() ?? '';
  if (!title) {
    defects.push({ dimension: 'title', severity: 'high', code: 'title_missing', message: 'Recipe has no title.' });
    return 0;
  }

  let score = 1;

  if (title.length < 4) {
    defects.push({ dimension: 'title', severity: 'high', code: 'title_too_short', message: `Title is implausibly short: "${title}".`, sample: title });
    score -= 0.5;
  }
  if (title.length > 90) {
    defects.push({ dimension: 'title', severity: 'medium', code: 'title_too_long', message: 'Title is very long — likely a blog headline rather than a dish name.', sample: truncate(title) });
    score -= 0.25;
  }
  if (/[|]|\s[–-]\s/.test(title) && /\.(com|net|org)|recipes?$|kitchen$|eats$/i.test(title)) {
    defects.push({ dimension: 'title', severity: 'medium', code: 'title_site_suffix', message: 'Title appears to carry a trailing site name.', sample: truncate(title) });
    score -= 0.25;
  }
  if (EMOJI.test(title) || HASHTAG.test(title)) {
    defects.push({ dimension: 'title', severity: 'medium', code: 'title_social_noise', message: 'Title contains emoji or hashtags.', sample: truncate(title) });
    score -= 0.3;
  }
  if (/!{2,}/.test(title) || (title.match(/\b[A-Z]{3,}\b/g)?.length ?? 0) >= 2) {
    defects.push({ dimension: 'title', severity: 'low', code: 'title_clickbait', message: 'Title reads as clickbait (shouting caps / multiple exclamations).', sample: truncate(title) });
    score -= 0.15;
  }
  const genericTitles = new Set(['recipe', 'recipes', 'untitled', 'home', 'instagram', 'tiktok', 'facebook', 'video']);
  if (genericTitles.has(title.toLowerCase())) {
    defects.push({ dimension: 'title', severity: 'high', code: 'title_generic', message: `Title is a generic placeholder: "${title}".`, sample: title });
    score -= 0.6;
  }
  return clamp01(score);
}

function scoreIngredientIntegrity(draft: RecipeDraft, defects: RecipeQualityDefect[]): number {
  const ings = draft.ingredients ?? [];
  const n = ings.length;
  if (n === 0) {
    defects.push({ dimension: 'ingredientIntegrity', severity: 'high', code: 'ingredients_missing', message: 'Recipe has no ingredients.' });
    return 0;
  }

  let score = 1;

  // Count plausibility.
  if (n < 2) {
    defects.push({ dimension: 'ingredientIntegrity', severity: 'medium', code: 'ingredients_too_few', message: `Only ${n} ingredient — likely an incomplete parse.` });
    score -= 0.3;
  }
  if (n > 45) {
    defects.push({ dimension: 'ingredientIntegrity', severity: 'medium', code: 'ingredients_too_many', message: `${n} ingredients — likely list/section bleed or noise.` });
    score -= 0.3;
  }

  // Per-line junk + prose detection.
  let junkLines = 0;
  let proseLines = 0;
  for (const ing of ings) {
    const text = ing.rawText.trim();
    const lower = text.toLowerCase();
    const isJunk =
      looksLikeNutritionFact(text) ||
      NOISE_PHRASES.some((p) => lower.includes(p)) ||
      /^(print|scale|author|servings?|yield|course|cuisine|prep time|cook time|total time)\b/i.test(text) ||
      BARE_URL.test(text);
    if (isJunk) {
      junkLines += 1;
      continue;
    }
    // Prose: long ingredient lines that read as sentences (multiple commas /
    // a period mid-line / very long) usually mean a paragraph leaked in.
    if (text.length > 140 || (text.split(' ').length > 22)) proseLines += 1;
  }

  if (junkLines > 0) {
    const sample = ings.find((i) => {
      const lower = i.rawText.toLowerCase();
      return looksLikeNutritionFact(i.rawText) || NOISE_PHRASES.some((p) => lower.includes(p)) || BARE_URL.test(i.rawText);
    });
    defects.push({
      dimension: 'ingredientIntegrity',
      severity: junkLines >= 3 ? 'high' : 'medium',
      code: 'ingredients_junk_lines',
      message: `${junkLines} ingredient line(s) are junk (nutrition leak, nav/ad text, or a URL).`,
      sample: sample ? truncate(sample.rawText) : undefined,
    });
    score -= Math.min(0.5, junkLines * 0.12);
  }
  if (proseLines > 0) {
    defects.push({ dimension: 'ingredientIntegrity', severity: 'medium', code: 'ingredients_prose', message: `${proseLines} ingredient line(s) read as prose/paragraphs rather than items.` });
    score -= Math.min(0.3, proseLines * 0.1);
  }

  // Duplicates (case-insensitive on rawText).
  const seen = new Set<string>();
  let dupes = 0;
  for (const ing of ings) {
    const key = ing.rawText.trim().toLowerCase();
    if (seen.has(key)) dupes += 1;
    else seen.add(key);
  }
  if (dupes > 0) {
    defects.push({ dimension: 'ingredientIntegrity', severity: dupes >= 3 ? 'medium' : 'low', code: 'ingredients_duplicates', message: `${dupes} duplicate ingredient line(s).` });
    score -= Math.min(0.25, dupes * 0.08);
  }

  return clamp01(score);
}

function scoreIngredientParseability(draft: RecipeDraft, defects: RecipeQualityDefect[]): number {
  const ings = draft.ingredients ?? [];
  if (ings.length === 0) return 0;

  const parseable = ings.filter((i) => looksParseableIngredient(i.rawText)).length;
  const fraction = parseable / ings.length;

  // Many legit ingredients lack a quantity ("salt to taste"), so we don't
  // require 100%. ~75%+ parseable lines earns full marks.
  const score = clamp01(fraction / 0.75);

  if (fraction < 0.5) {
    defects.push({
      dimension: 'ingredientParseability',
      severity: fraction < 0.25 ? 'high' : 'medium',
      code: 'ingredients_unparseable',
      message: `Only ${Math.round(fraction * 100)}% of ingredient lines have a recognizable quantity/unit shape.`,
    });
  }

  // Implementation-gap flag: the structured fields exist but the importer
  // never populates them, so the app can't do per-ingredient scaling/sub.
  const structured = ings.filter((i) => i.quantityText || i.unitText || i.ingredientName).length;
  if (structured === 0 && parseable > 0) {
    defects.push({
      dimension: 'ingredientParseability',
      severity: 'low',
      code: 'ingredients_unstructured_fields',
      message: 'rawText is parseable but quantityText/unitText/ingredientName are never populated — no structured fields for scaling or substitution.',
    });
  }

  return score;
}

function scoreStepIntegrity(draft: RecipeDraft, defects: RecipeQualityDefect[]): number {
  const steps = draft.steps ?? [];
  const n = steps.length;
  if (n === 0) {
    defects.push({ dimension: 'stepIntegrity', severity: 'high', code: 'steps_missing', message: 'Recipe has no instructions.' });
    return 0;
  }

  let score = 1;

  if (n === 1 && steps[0].text.length > 250) {
    defects.push({ dimension: 'stepIntegrity', severity: 'high', code: 'steps_prose_blob', message: 'All instructions are crammed into a single long paragraph — not split into steps.', sample: truncate(steps[0].text, 120) });
    score -= 0.5;
  }
  if (n > 40) {
    defects.push({ dimension: 'stepIntegrity', severity: 'medium', code: 'steps_too_many', message: `${n} steps — likely over-split or noise.` });
    score -= 0.25;
  }

  let nonInstruction = 0;
  let junkSteps = 0;
  for (const step of steps) {
    const text = step.text.trim();
    const lower = text.toLowerCase();
    if (NOISE_PHRASES.some((p) => lower.includes(p)) || BARE_URL.test(text) || HASHTAG.test(text)) {
      junkSteps += 1;
      continue;
    }
    // A real step either starts with / contains a cooking verb, or is long
    // enough to plausibly be an instruction sentence. Short verbless lines
    // ("Notes", "For the sauce") are headings, not steps.
    if (!firstCookingVerbWord(text) && text.length < 40) nonInstruction += 1;
  }

  if (junkSteps > 0) {
    defects.push({ dimension: 'stepIntegrity', severity: junkSteps >= 2 ? 'high' : 'medium', code: 'steps_junk', message: `${junkSteps} step(s) are nav/ad/social cruft rather than instructions.` });
    score -= Math.min(0.5, junkSteps * 0.2);
  }
  if (nonInstruction > 0) {
    defects.push({ dimension: 'stepIntegrity', severity: 'low', code: 'steps_non_instruction', message: `${nonInstruction} step(s) look like headings/labels, not actions.` });
    score -= Math.min(0.3, nonInstruction * 0.1);
  }

  // Average step length sanity: extremely short steps ("Mix.") across the
  // board, or one giant blob, both read poorly.
  const avgLen = steps.reduce((sum, s) => sum + s.text.trim().length, 0) / n;
  if (avgLen < 15) {
    defects.push({ dimension: 'stepIntegrity', severity: 'low', code: 'steps_too_terse', message: 'Steps are extremely terse on average — may be fragmented.' });
    score -= 0.15;
  }

  return clamp01(score);
}

function scoreMetadata(draft: RecipeDraft, defects: RecipeQualityDefect[]): number {
  let score = 1;
  const hasServings = !!draft.servings?.trim();
  const hasAnyTime = !!(draft.prepTime?.trim() || draft.cookTime?.trim() || draft.totalTime?.trim());

  if (!hasServings) {
    defects.push({ dimension: 'metadata', severity: 'medium', code: 'servings_missing', message: 'No servings/yield.' });
    score -= 0.5;
  }
  if (!hasAnyTime) {
    defects.push({ dimension: 'metadata', severity: 'medium', code: 'times_missing', message: 'No prep/cook/total time.' });
    score -= 0.5;
  }
  return clamp01(score);
}

function scoreMedia(draft: RecipeDraft, defects: RecipeQualityDefect[]): number {
  let score = 1;
  if (!draft.heroImageUrl?.trim()) {
    defects.push({ dimension: 'media', severity: 'low', code: 'image_missing', message: 'No hero image.' });
    score -= 0.6;
  }
  if (!draft.sourceDomain?.trim()) {
    defects.push({ dimension: 'media', severity: 'medium', code: 'attribution_missing', message: 'No source domain for attribution.' });
    score -= 0.4;
  }
  return clamp01(score);
}

function scoreNoiseFree(draft: RecipeDraft, defects: RecipeQualityDefect[]): number {
  const texts = collectAllText(draft);
  let hits = 0;
  const seenCodes = new Set<string>();

  for (const text of texts) {
    const lower = text.toLowerCase();
    for (const phrase of NOISE_PHRASES) {
      if (lower.includes(phrase)) {
        hits += 1;
        if (!seenCodes.has('noise_phrase')) {
          defects.push({ dimension: 'noiseFree', severity: 'high', code: 'noise_phrase', message: `Blog/ad/social boilerplate present (e.g. "${phrase}").`, sample: truncate(text) });
          seenCodes.add('noise_phrase');
        }
      }
    }
    if (HASHTAG.test(text)) { hits += 1; if (!seenCodes.has('noise_hashtag')) { defects.push({ dimension: 'noiseFree', severity: 'medium', code: 'noise_hashtag', message: 'Hashtags present in recipe text.', sample: truncate(text) }); seenCodes.add('noise_hashtag'); } }
    if (MENTION.test(text)) { hits += 1; if (!seenCodes.has('noise_mention')) { defects.push({ dimension: 'noiseFree', severity: 'low', code: 'noise_mention', message: '@mentions present in recipe text.', sample: truncate(text) }); seenCodes.add('noise_mention'); } }
    if (BARE_URL.test(text)) { hits += 1; if (!seenCodes.has('noise_url')) { defects.push({ dimension: 'noiseFree', severity: 'medium', code: 'noise_url', message: 'Raw URL present in recipe text.', sample: truncate(text) }); seenCodes.add('noise_url'); } }
    if (EMOJI.test(text)) { hits += 1; if (!seenCodes.has('noise_emoji')) { defects.push({ dimension: 'noiseFree', severity: 'low', code: 'noise_emoji', message: 'Emoji present in recipe text.', sample: truncate(text) }); seenCodes.add('noise_emoji'); } }
  }

  // Each distinct hit knocks the dimension down; a couple of hits is "fair",
  // 5+ is "poor".
  return clamp01(1 - hits * 0.18);
}

// MARK: - Entry point

export function scoreRecipeDraft(draft: RecipeDraft): RecipeQualityReport {
  const defects: RecipeQualityDefect[] = [];

  const dimensions: Record<QualityDimension, number> = {
    title: scoreTitle(draft, defects),
    ingredientIntegrity: scoreIngredientIntegrity(draft, defects),
    ingredientParseability: scoreIngredientParseability(draft, defects),
    stepIntegrity: scoreStepIntegrity(draft, defects),
    metadata: scoreMetadata(draft, defects),
    media: scoreMedia(draft, defects),
    noiseFree: scoreNoiseFree(draft, defects),
  };

  let overall = 0;
  for (const dim of Object.keys(dimensions) as QualityDimension[]) {
    overall += dimensions[dim] * DIMENSION_WEIGHTS[dim];
  }
  overall = Math.round(overall);

  const band: RecipeQualityReport['band'] =
    overall >= 85 ? 'excellent' : overall >= 70 ? 'good' : overall >= 50 ? 'fair' : 'poor';

  return { overall, band, dimensions, defects };
}

export const __testing = {
  DIMENSION_WEIGHTS,
  looksParseableIngredient,
  firstCookingVerbWord,
};
