import { isIP } from 'node:net';
import type { PoolClient } from 'pg';
import getRecipeData from '@dimfu/recipe-scraper';
import { pool } from '../db.js';
import { ApiError } from '../utils/errors.js';
import { ensureUserExists } from './userService.js';

const SCRAPE_TIMEOUT_MS = 8000;
const READER_TIMEOUT_MS = 20000;
const MAX_REDIRECTS = 3;
const MAX_HTML_BYTES = 3_000_000;
const MAX_MARKDOWN_BYTES = 800_000;
const READER_BASE_URL = 'https://r.jina.ai/http://';
const READER_FALLBACK_STATUSES = new Set([401, 402, 403, 406, 429, 451]);

type AuthContext = {
  authProvider?: string | null;
  userEmail?: string | null;
};

type ScrapedRecipe = Partial<{
  url: string;
  name: string;
  image: string;
  description: string;
  cookTime: string;
  prepTime: string;
  totalTime: string;
  recipeYield: string | number;
  recipeIngredients: unknown[];
  recipeInstructions: unknown[];
  recipeCategories: unknown[];
  recipeCuisines: unknown[];
  keywords: unknown[];
}>;

export type RecipeIngredientDraft = {
  rawText: string;
  quantityText: string | null;
  unitText: string | null;
  ingredientName: string | null;
};

export type RecipeStepDraft = {
  text: string;
};

export type RecipeDraft = {
  title: string;
  sourceUrl: string;
  sourceDomain: string;
  sourceName: string | null;
  heroImageUrl: string | null;
  description: string | null;
  servings: string | null;
  prepTime: string | null;
  cookTime: string | null;
  totalTime: string | null;
  categories: string[];
  cuisines: string[];
  keywords: string[];
  ingredients: RecipeIngredientDraft[];
  steps: RecipeStepDraft[];
  confidence: number;
  warnings: string[];
};

export type SavedRecipeInput = Omit<RecipeDraft, 'confidence' | 'warnings' | 'sourceDomain'> & {
  importId?: string | null;
  nutrition?: unknown;
};

export type SavedRecipe = Omit<RecipeDraft, 'confidence' | 'warnings'> & {
  id: string;
  importId: string | null;
  nutrition: unknown | null;
  createdAt: string;
  updatedAt: string;
};

type RecipeRow = {
  id: string;
  import_id: string | null;
  title: string;
  source_url: string;
  source_domain: string;
  source_name: string | null;
  hero_image_url: string | null;
  description: string | null;
  servings: string | null;
  prep_time: string | null;
  cook_time: string | null;
  total_time: string | null;
  categories: string[] | null;
  cuisines: string[] | null;
  keywords: string[] | null;
  nutrition_json: unknown | null;
  ingredients: unknown;
  steps: unknown;
  created_at: Date;
  updated_at: Date;
};

type SafeRecipeUrl = {
  url: string;
  domain: string;
};

type RecipeHtmlPayload = {
  finalUrl: string;
  html: string;
};

type RecipeMarkdownPayload = {
  finalUrl: string;
  markdown: string;
};

function cleanString(value: unknown, maxLength = 1000): string | null {
  if (typeof value !== 'string' && typeof value !== 'number') {
    return null;
  }
  const trimmed = String(value).replace(/\s+/g, ' ').trim();
  if (!trimmed) {
    return null;
  }
  return trimmed.slice(0, maxLength);
}

function compactStringList(values: unknown, maxItemLength = 220): string[] {
  if (!Array.isArray(values)) {
    return [];
  }
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const cleaned = cleanString(value, maxItemLength);
    if (!cleaned || seen.has(cleaned.toLowerCase())) {
      continue;
    }
    seen.add(cleaned.toLowerCase());
    result.push(cleaned);
  }
  return result;
}

function cleanMarkdownText(value: string, maxLength = 1000): string | null {
  const cleaned = value
    .replace(/!\[[^\]]*]\([^)]*\)/g, '')
    .replace(/\[([^\]]+)]\([^)]*\)/g, ' $1')
    .replace(/\*\*([^*]+)\*\*/g, ' $1 ')
    .replace(/[_`]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  return cleanString(cleaned, maxLength);
}

function normalizeHostname(hostname: string): string {
  return hostname.toLowerCase().replace(/^\[/, '').replace(/\]$/, '').replace(/\.$/, '');
}

function sourceDomainFor(hostname: string): string {
  return normalizeHostname(hostname).replace(/^www\./, '');
}

function isPrivateIpv4(hostname: string): boolean {
  const parts = hostname.split('.').map((part) => Number(part));
  if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) {
    return false;
  }
  const [a, b] = parts;
  return (
    a === 0 ||
    a === 10 ||
    a === 127 ||
    (a === 100 && b >= 64 && b <= 127) ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) ||
    (a === 198 && (b === 18 || b === 19)) ||
    a >= 224
  );
}

function isPrivateIpv6(hostname: string): boolean {
  const normalized = normalizeHostname(hostname);
  if (normalized === '::' || normalized === '::1') {
    return true;
  }
  if (normalized.startsWith('fc') || normalized.startsWith('fd') || normalized.startsWith('fe80:')) {
    return true;
  }
  if (normalized.startsWith('::ffff:')) {
    return isPrivateIpv4(normalized.slice('::ffff:'.length));
  }
  return false;
}

export function assertSafeRecipeUrl(rawUrl: string): SafeRecipeUrl {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new ApiError(400, 'RECIPE_IMPORT_INVALID_URL', 'Recipe URL is not valid');
  }

  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new ApiError(400, 'RECIPE_IMPORT_INVALID_URL', 'Recipe URL must use http or https');
  }

  const hostname = normalizeHostname(parsed.hostname);
  if (!hostname) {
    throw new ApiError(400, 'RECIPE_IMPORT_INVALID_URL', 'Recipe URL must include a host');
  }

  if (
    hostname === 'localhost' ||
    hostname.endsWith('.localhost') ||
    hostname.endsWith('.local') ||
    hostname === 'ip6-localhost' ||
    hostname === 'ip6-loopback'
  ) {
    throw new ApiError(400, 'RECIPE_IMPORT_UNSAFE_URL', 'Recipe URL must be a public web page');
  }

  const ipVersion = isIP(hostname);
  if ((ipVersion === 4 && isPrivateIpv4(hostname)) || (ipVersion === 6 && isPrivateIpv6(hostname))) {
    throw new ApiError(400, 'RECIPE_IMPORT_UNSAFE_URL', 'Recipe URL must be a public web page');
  }

  parsed.hash = '';
  return {
    url: parsed.toString(),
    domain: sourceDomainFor(hostname)
  };
}

async function fetchRecipeHtml(startUrl: string): Promise<RecipeHtmlPayload> {
  let currentUrl = startUrl;
  for (let redirectCount = 0; redirectCount <= MAX_REDIRECTS; redirectCount += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), SCRAPE_TIMEOUT_MS);
    let response: Response;
    try {
      response = await fetch(currentUrl, {
        method: 'GET',
        redirect: 'manual',
        signal: controller.signal,
        headers: {
          accept: 'text/html,application/xhtml+xml',
          'user-agent': 'FoodAppRecipeImporter/1.0 (+https://food.app)'
        }
      });
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        throw new ApiError(504, 'RECIPE_IMPORT_TIMEOUT', 'Recipe page took too long to respond');
      }
      throw new ApiError(502, 'RECIPE_IMPORT_FETCH_FAILED', 'Could not fetch the recipe page');
    } finally {
      clearTimeout(timeout);
    }

    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get('location');
      if (!location) {
        throw new ApiError(502, 'RECIPE_IMPORT_FETCH_FAILED', 'Recipe page redirected without a destination');
      }
      if (redirectCount === MAX_REDIRECTS) {
        throw new ApiError(502, 'RECIPE_IMPORT_TOO_MANY_REDIRECTS', 'Recipe page redirected too many times');
      }
      currentUrl = assertSafeRecipeUrl(new URL(location, currentUrl).toString()).url;
      continue;
    }

    if (!response.ok) {
      const code = READER_FALLBACK_STATUSES.has(response.status)
        ? 'RECIPE_IMPORT_SITE_BLOCKED'
        : 'RECIPE_IMPORT_FETCH_FAILED';
      throw new ApiError(502, code, `Recipe page returned HTTP ${response.status}`);
    }

    const contentType = response.headers.get('content-type')?.toLowerCase() ?? '';
    if (contentType && !contentType.includes('text/html') && !contentType.includes('application/xhtml+xml')) {
      throw new ApiError(415, 'RECIPE_IMPORT_UNSUPPORTED_CONTENT', 'Recipe URL must point to an HTML page');
    }

    const contentLength = Number(response.headers.get('content-length') ?? '0');
    if (Number.isFinite(contentLength) && contentLength > MAX_HTML_BYTES) {
      throw new ApiError(413, 'RECIPE_IMPORT_PAGE_TOO_LARGE', 'Recipe page is too large to import');
    }

    const html = await response.text();
    if (html.length > MAX_HTML_BYTES) {
      throw new ApiError(413, 'RECIPE_IMPORT_PAGE_TOO_LARGE', 'Recipe page is too large to import');
    }

    return { finalUrl: currentUrl, html };
  }

  throw new ApiError(502, 'RECIPE_IMPORT_TOO_MANY_REDIRECTS', 'Recipe page redirected too many times');
}

function readerUrlFor(sourceUrl: string): string {
  const parsed = new URL(sourceUrl);
  parsed.protocol = 'http:';
  parsed.hash = '';
  return `${READER_BASE_URL}${parsed.host}${parsed.pathname}${parsed.search}`;
}

async function fetchRecipeMarkdownViaReader(sourceUrl: string): Promise<RecipeMarkdownPayload> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), READER_TIMEOUT_MS);
  let response: Response;

  try {
    response = await fetch(readerUrlFor(sourceUrl), {
      method: 'GET',
      redirect: 'follow',
      signal: controller.signal,
      headers: {
        accept: 'text/plain, text/markdown',
        'user-agent': 'FoodAppRecipeImporter/1.0 (+https://food.app)'
      }
    });
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      throw new ApiError(504, 'RECIPE_IMPORT_TIMEOUT', 'Recipe page took too long to respond');
    }
    throw new ApiError(
      502,
      'RECIPE_IMPORT_SITE_BLOCKED',
      'That recipe site blocked direct import. Try another recipe page.'
    );
  } finally {
    clearTimeout(timeout);
  }

  if (!response.ok) {
    throw new ApiError(
      502,
      'RECIPE_IMPORT_SITE_BLOCKED',
      'That recipe site blocked direct import. Try another recipe page.'
    );
  }

  const contentLength = Number(response.headers.get('content-length') ?? '0');
  if (Number.isFinite(contentLength) && contentLength > MAX_MARKDOWN_BYTES) {
    throw new ApiError(413, 'RECIPE_IMPORT_PAGE_TOO_LARGE', 'Recipe page is too large to import');
  }

  const markdown = await response.text();
  if (markdown.length > MAX_MARKDOWN_BYTES) {
    throw new ApiError(413, 'RECIPE_IMPORT_PAGE_TOO_LARGE', 'Recipe page is too large to import');
  }

  return { finalUrl: sourceUrl, markdown };
}

function markdownLines(markdown: string): string[] {
  return markdown.split(/\r?\n/).map((line) => line.trim());
}

type MarkdownHeading = {
  level: number;
  text: string;
};

function stripMarkdownListPrefix(line: string): string {
  return line
    .replace(/^\*\s+/, '')
    .replace(/^-\s+\[[ xX]\]\s*/, '')
    .replace(/^\[[ xX]\]\s*/, '')
    .replace(/^[-+]\s+/, '')
    .trim();
}

function markdownHeading(line: string): MarkdownHeading | null {
  const match = line.match(/^(#{1,6})\s+(.+)$/);
  if (!match) {
    return null;
  }

  const text = cleanMarkdownText(match[2]!, 220);
  return text ? { level: match[1]!.length, text } : null;
}

function normalizedMarkdownLabel(value: string): string {
  return value
    .replace(/\s+recipe$/i, '')
    .replace(/[:.!?]+$/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

function markdownCleanLine(line: string, maxLength = 1000): string | null {
  return cleanMarkdownText(stripMarkdownListPrefix(line), maxLength);
}

function markdownRecipeCardStartIndex(lines: string[]): number {
  return lines.findIndex((line, index) => {
    const heading = markdownHeading(line);
    if (!heading || heading.level !== 2) {
      return false;
    }

    const headingKey = normalizedMarkdownLabel(heading.text);
    if (['ingredients', 'instructions', 'directions', 'method', 'nutrition'].includes(headingKey)) {
      return false;
    }

    const preview = lines
      .slice(index, index + 90)
      .map((candidate) => markdownCleanLine(candidate, 220) ?? candidate)
      .join('\n')
      .toLowerCase();
    const hasTiming = preview.includes('prep time') || preview.includes('cook time') || preview.includes('total time');
    const hasRecipeParts =
      preview.includes('ingredients') ||
      preview.includes('instructions') ||
      preview.includes('directions') ||
      preview.includes('cook mode');
    return hasTiming && hasRecipeParts;
  });
}

function cleanRecipeTitleCandidate(value: string): string | null {
  const cleaned = cleanMarkdownText(
    value
      .replace(/\s+\|\s+.+$/g, '')
      .replace(/\s+-\s+[A-Z][A-Za-z0-9 '&.]+$/g, '')
      .replace(/\s+Recipe$/i, ''),
    180
  );
  if (!cleaned || /^(just a moment|access denied|page not found)$/i.test(cleaned)) {
    return null;
  }
  return cleaned;
}

function markdownHeadingTitle(lines: string[]): string | null {
  const titleLine = lines.find((line) => line.toLowerCase().startsWith('title:'));
  const explicitTitle = titleLine ? cleanRecipeTitleCandidate(titleLine.slice('title:'.length)) : null;
  if (explicitTitle) {
    return explicitTitle;
  }

  const cardStartIndex = markdownRecipeCardStartIndex(lines);
  if (cardStartIndex >= 0) {
    const heading = markdownHeading(lines[cardStartIndex]!);
    const title = heading ? cleanRecipeTitleCandidate(heading.text) : null;
    if (title) {
      return title;
    }
  }

  for (const line of lines) {
    const match = line.match(/^#\s+(.+)$/);
    const title = match ? cleanRecipeTitleCandidate(match[1]!) : null;
    if (title) {
      return title;
    }
  }
  return null;
}

function escapedRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function cleanMetadataValue(value: string, maxLength = 120): string | null {
  return cleanMarkdownText(
    value.replace(/\s+(?:active|cook|cook time|makes|prep|prep time|serves|total|total time|yield)\b.*$/i, ''),
    maxLength
  );
}

function cleanServingsValue(value: string): string | null {
  return cleanMarkdownText(value.replace(/\s+(?:active|cook|cook time|makes|prep|prep time|total|total time|yield)\b.*$/i, ''), 120);
}

function markdownValueAfterLabel(lines: string[], label: string): string | null {
  const normalizedLabel = label.toLowerCase();
  const labelPattern = escapedRegExp(label);
  for (let index = 0; index < lines.length; index += 1) {
    const line = markdownCleanLine(lines[index]!, 240);
    if (!line) {
      continue;
    }

    const lower = line.toLowerCase();
    if (lower.startsWith(`${normalizedLabel}:`)) {
      const inlineValue = cleanMetadataValue(line.slice(line.indexOf(':') + 1), 120);
      if (inlineValue) {
        return inlineValue;
      }
    }

    const noColonMatch = line.match(new RegExp(`^${labelPattern}\\s+(.+)$`, 'i'));
    if (noColonMatch) {
      const inlineValue = cleanMetadataValue(noColonMatch[1]!, 120);
      if (inlineValue) {
        return inlineValue;
      }
    }

    if (line.replace(/:$/, '').toLowerCase() !== normalizedLabel) {
      continue;
    }
    for (const candidate of lines.slice(index + 1, index + 8)) {
      if (!candidate || candidate.startsWith('#')) {
        continue;
      }
      const value = markdownCleanLine(candidate, 120);
      if (value) {
        return value;
      }
    }
  }
  return null;
}

function markdownServings(lines: string[]): string | null {
  const labeled = markdownValueAfterLabel(lines, 'Servings') ?? markdownValueAfterLabel(lines, 'Yield');
  if (labeled) {
    return labeled;
  }

  for (const line of lines) {
    const cleanedLine = markdownCleanLine(line, 160);
    if (!cleanedLine) {
      continue;
    }
    const servesMatch = cleanedLine.match(/^serves\s+(.+)$/i);
    if (servesMatch) {
      return cleanServingsValue(servesMatch[1]!);
    }
    const cutsMatch = cleanedLine.match(/^cuts into\s+(.+)$/i);
    if (cutsMatch) {
      return cleanMarkdownText(cutsMatch[1]!, 120);
    }
  }
  return null;
}

function markdownRecipeCardLines(lines: string[]): string[] {
  const startIndex = markdownRecipeCardStartIndex(lines);
  if (startIndex < 0) {
    return [];
  }

  const startHeading = markdownHeading(lines[startIndex]!);
  const endIndex = lines.findIndex((line, index) => {
    if (index <= startIndex) {
      return false;
    }
    const heading = markdownHeading(line);
    return Boolean(heading && startHeading && heading.level <= startHeading.level);
  });
  return lines.slice(startIndex + 1, endIndex < 0 ? undefined : endIndex);
}

function markdownBulletText(line: string, maxLength: number): string | null {
  const bullet = line.match(/^(?:\*|-|\+)\s+(.+)$/)?.[1];
  if (!bullet) {
    return null;
  }
  return cleanMarkdownText(stripMarkdownListPrefix(bullet), maxLength);
}

function markdownInputText(line: string, maxLength: number): string | null {
  const input = line.match(/^\[Input]\s+(.+)$/)?.[1];
  if (!input) {
    return null;
  }
  const cleaned = cleanMarkdownText(input, maxLength);
  if (!cleaned || /^(deselect all|add to shopping list|view shopping list|ingredient substitutions)$/i.test(cleaned)) {
    return null;
  }
  return cleaned;
}

function markdownOrderedText(line: string, maxLength: number): string | null {
  const ordered = line.match(/^\d+\.\s+(.+)$/)?.[1];
  return ordered ? cleanMarkdownText(ordered, maxLength) : null;
}

function isIngredientNoise(text: string): boolean {
  const lower = text.toLowerCase();
  return (
    lower === '* *' ||
    lower === 'print' ||
    lower.startsWith('author:') ||
    lower.startsWith('category:') ||
    lower.startsWith('method:') ||
    lower.startsWith('cuisine:') ||
    lower.startsWith('diet:') ||
    lower.startsWith('prep time:') ||
    lower.startsWith('cook time:') ||
    lower.startsWith('total time:') ||
    lower.startsWith('yield:') ||
    lower.startsWith('servings:') ||
    lower.startsWith('scale') ||
    lower.startsWith('pin recipe') ||
    lower.startsWith('cook mode') ||
    lower.includes('prevent your screen') ||
    /^(kcal|calories|carbohydrates|protein|fat|saturated fat|saturates|trans fat|cholesterol|sodium|carbs|sugars|fibre|fiber|salt)\b/i.test(
      text
    )
  );
}

function isInstructionNoise(text: string): boolean {
  const lower = text.toLowerCase();
  return lower === '* *' || lower.startsWith('video ') || lower.startsWith('notes') || lower.startsWith('nutrition');
}

function isInstructionLike(text: string): boolean {
  return /^(add|arrange|bake|bring|chill|combine|cook|cover|divide|drain|fill|fold|heat|in a|line|make|mix|noodles:|once|pour|preheat|reduce|refrigerate|remove|roll|serve|set aside|simmer|stir|strain|taste|to serve|top|transfer|use|when|whisk)\b/i.test(
    text
  );
}

function isQuantityOnlyIngredientPart(text: string): boolean {
  return (
    text.length <= 28 &&
    /^\d/.test(text) &&
    !/[,.]/.test(text) &&
    !/\b(?:and|or|with|plus|divided|trimmed|chopped|diced|minced|sliced|grated|ground|fresh|frozen)\b/i.test(text)
  );
}

function collectIngredientsFromLines(lines: string[]): string[] {
  const ingredients: string[] = [];
  let hasCollectedIngredient = false;

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index]!;
    const heading = markdownHeading(line);
    if (heading) {
      const headingKey = normalizedMarkdownLabel(heading.text);
      if (
        [
          'method',
          'directions',
          'instructions',
          'notes',
          'recipe notes',
          'frequently asked questions',
          'comments',
          'reader interactions'
        ].includes(headingKey)
      ) {
        break;
      }
      if (headingKey === 'nutrition' || headingKey === 'nutrition facts') {
        if (hasCollectedIngredient) {
          break;
        }
        continue;
      }
      continue;
    }

    let ingredient = markdownBulletText(line, 700) ?? markdownInputText(line, 700);
    if (ingredient && isQuantityOnlyIngredientPart(ingredient)) {
      for (let nextIndex = index + 1; nextIndex < Math.min(index + 4, lines.length); nextIndex += 1) {
        const nextLine = lines[nextIndex]!;
        if (
          !nextLine ||
          markdownHeading(nextLine) ||
          markdownBulletText(nextLine, 700) ||
          markdownOrderedText(nextLine, 700) ||
          markdownInputText(nextLine, 700)
        ) {
          continue;
        }
        const nextText = markdownCleanLine(nextLine, 700);
        if (nextText && !isIngredientNoise(nextText)) {
          ingredient = `${ingredient} ${nextText}`;
          index = nextIndex;
          break;
        }
      }
    }
    if (!ingredient || isIngredientNoise(ingredient)) {
      continue;
    }
    ingredients.push(ingredient);
    hasCollectedIngredient = true;
  }

  return ingredients;
}

function markdownIngredientSection(lines: string[]): string[] {
  const startIndex = lines.findIndex((line) => {
    const heading = markdownHeading(line);
    return Boolean(heading && heading.level <= 4 && normalizedMarkdownLabel(heading.text) === 'ingredients');
  });
  return startIndex < 0 ? [] : collectIngredientsFromLines(lines.slice(startIndex + 1));
}

function markdownInstructionSection(lines: string[]): string[] {
  const startIndex = lines.findIndex((line) => {
    const heading = markdownHeading(line);
    if (!heading) {
      return false;
    }
    const headingKey = normalizedMarkdownLabel(heading.text);
    return ['directions', 'instructions', 'method'].includes(headingKey);
  });
  if (startIndex < 0) {
    return [];
  }

  const startHeading = markdownHeading(lines[startIndex]!);
  const steps: string[] = [];
  let stepParts: string[] = [];
  let isCollectingStepBlock = false;
  const flushStepBlock = () => {
    const text = cleanMarkdownText(stepParts.join(' '), 2000);
    if (text && !isInstructionNoise(text)) {
      steps.push(text);
    }
    stepParts = [];
  };

  for (const line of lines.slice(startIndex + 1)) {
    const heading = markdownHeading(line);
    if (heading && startHeading && heading.level <= startHeading.level) {
      break;
    }

    const stepMarker = line.match(/^(?:\*\s+)?#{1,6}\s*step\s+\d+/i);
    if (stepMarker) {
      flushStepBlock();
      isCollectingStepBlock = true;
      continue;
    }

    const ordered = markdownOrderedText(line, 2000);
    if (ordered && !isInstructionNoise(ordered)) {
      flushStepBlock();
      isCollectingStepBlock = false;
      steps.push(ordered);
      continue;
    }

    const bullet = markdownBulletText(line, 2000);
    if (bullet && !isInstructionNoise(bullet)) {
      if (isCollectingStepBlock) {
        stepParts.push(bullet);
      } else {
        steps.push(bullet);
      }
      continue;
    }

    const text = markdownCleanLine(line, 2000);
    if (text && isCollectingStepBlock && !isInstructionNoise(text)) {
      stepParts.push(text);
    }
  }
  flushStepBlock();

  return steps;
}

function markdownStepsAfterIngredients(lines: string[]): string[] {
  const startIndex = lines.findIndex((line) => {
    const heading = markdownHeading(line);
    return Boolean(heading && heading.level <= 4 && normalizedMarkdownLabel(heading.text) === 'ingredients');
  });
  if (startIndex < 0) {
    return [];
  }

  const steps: string[] = [];
  let hasStartedSteps = false;

  for (const line of lines.slice(startIndex + 1)) {
    const heading = markdownHeading(line);
    if (heading) {
      const headingKey = normalizedMarkdownLabel(heading.text);
      if (['recipe notes', 'notes', 'nutrition', 'nutrition facts', 'comments', 'reader interactions'].includes(headingKey)) {
        break;
      }
      if (['directions', 'instructions', 'method'].includes(headingKey)) {
        continue;
      }
    }

    const ordered = markdownOrderedText(line, 2000);
    if (ordered && !isInstructionNoise(ordered)) {
      hasStartedSteps = true;
      steps.push(ordered);
      continue;
    }

    if (hasStartedSteps && markdownBulletText(line, 2000)) {
      break;
    }
  }

  return steps;
}

function markdownIngredientsBeforeCookMode(lines: string[]): string[] {
  const cookModeIndex = lines.findIndex((line) => (markdownCleanLine(line, 120) ?? '').toLowerCase().startsWith('cook mode'));
  if (cookModeIndex < 0) {
    return [];
  }

  const ingredients: string[] = [];
  for (let index = cookModeIndex - 1; index >= 0; index -= 1) {
    const line = lines[index]!;
    const ingredient = markdownBulletText(line, 700);
    if (ingredient && !isIngredientNoise(ingredient)) {
      ingredients.push(ingredient);
      continue;
    }

    if (!line || line === '* * *') {
      continue;
    }

    if (ingredients.length > 0) {
      break;
    }
  }

  return ingredients.reverse();
}

function markdownStepsAfterCookMode(lines: string[]): string[] {
  const cookModeIndex = lines.findIndex((line) => (markdownCleanLine(line, 120) ?? '').toLowerCase().startsWith('cook mode'));
  if (cookModeIndex < 0) {
    return [];
  }

  const steps: string[] = [];
  for (const line of lines.slice(cookModeIndex + 1)) {
    const heading = markdownHeading(line);
    if (heading && ['notes', 'nutrition', 'did you make this recipe', 'reader interactions'].includes(normalizedMarkdownLabel(heading.text))) {
      break;
    }

    const ordered = markdownOrderedText(line, 2000);
    const bullet = markdownBulletText(line, 2000);
    const step = ordered ?? bullet;
    if (step && !isInstructionNoise(step)) {
      steps.push(step);
    }
  }

  return steps;
}

function markdownContiguousRecipeLists(lines: string[]): { ingredients: string[]; steps: string[] } {
  const timeIndex = lines.findIndex((line) => {
    const cleaned = markdownCleanLine(line, 160)?.toLowerCase() ?? '';
    return cleaned.startsWith('total time') || cleaned.startsWith('cook time') || cleaned.startsWith('prep time');
  });
  const awakeIndex = lines.findIndex((line) => {
    const cleaned = markdownCleanLine(line, 160)?.toLowerCase() ?? '';
    return cleaned === 'keep screen awake' || cleaned.startsWith('cook mode');
  });
  const searchStartIndex = timeIndex >= 0 ? timeIndex : awakeIndex;
  if (searchStartIndex < 0) {
    return { ingredients: [], steps: [] };
  }

  const firstBulletIndex = lines.findIndex((line, index) => index > searchStartIndex && Boolean(markdownBulletText(line, 700)));
  if (firstBulletIndex < 0) {
    return { ingredients: [], steps: [] };
  }

  const ingredients: string[] = [];
  const steps: string[] = [];
  let isCollectingSteps = false;

  for (const line of lines.slice(firstBulletIndex)) {
    const heading = markdownHeading(line);
    if (heading && ['did you make this recipe', 'reader interactions', 'comments', 'notes'].includes(normalizedMarkdownLabel(heading.text))) {
      break;
    }

    const ordered = markdownOrderedText(line, 2000);
    if (ordered && !isInstructionNoise(ordered)) {
      isCollectingSteps = true;
      steps.push(ordered);
      continue;
    }

    const bullet = markdownBulletText(line, 2000);
    if (!bullet) {
      const cleaned = markdownCleanLine(line, 160);
      if (isCollectingSteps && cleaned && /^video\s+\d+/i.test(cleaned)) {
        break;
      }
      continue;
    }

    if (!isCollectingSteps && isInstructionLike(bullet)) {
      isCollectingSteps = true;
    }

    if (isCollectingSteps) {
      if (!isInstructionNoise(bullet)) {
        steps.push(bullet);
      }
    } else if (!isIngredientNoise(bullet)) {
      ingredients.push(bullet);
    }
  }

  return { ingredients, steps };
}

function markdownRecipeCardIngredients(lines: string[]): string[] {
  const cardLines = markdownRecipeCardLines(lines);
  if (cardLines.length === 0) {
    return [];
  }

  const explicitStart = cardLines.findIndex((line) => {
    const heading = markdownHeading(line);
    return Boolean(heading && normalizedMarkdownLabel(heading.text) === 'ingredients');
  });
  if (explicitStart >= 0) {
    return collectIngredientsFromLines(cardLines.slice(explicitStart + 1));
  }

  const ingredients: string[] = [];
  for (const line of cardLines) {
    const lower = (markdownCleanLine(line, 240) ?? line).toLowerCase();
    if (lower.startsWith('cook mode') || lower.startsWith('instructions') || lower.startsWith('directions')) {
      break;
    }
    const ingredient = markdownBulletText(line, 700);
    if (ingredient && !isIngredientNoise(ingredient)) {
      ingredients.push(ingredient);
    }
  }
  return ingredients;
}

function markdownRecipeCardSteps(lines: string[]): string[] {
  const cardLines = markdownRecipeCardLines(lines);
  const startIndex = cardLines.findIndex((line) => {
    const lower = line.toLowerCase();
    return lower.startsWith('cook mode') || lower.startsWith('instructions') || lower.startsWith('directions');
  });
  if (startIndex < 0) {
    return [];
  }

  const steps: string[] = [];
  for (const line of cardLines.slice(startIndex + 1)) {
    const heading = markdownHeading(line);
    if (heading && ['notes', 'nutrition'].includes(normalizedMarkdownLabel(heading.text))) {
      break;
    }
    const ordered = markdownOrderedText(line, 2000);
    const bullet = markdownBulletText(line, 2000);
    const step = ordered ?? bullet;
    if (step && !isInstructionNoise(step)) {
      steps.push(step);
    }
  }
  return steps;
}

function markdownIngredients(lines: string[]): string[] {
  const sectionIngredients = markdownIngredientSection(lines);
  if (sectionIngredients.length > 0) {
    return sectionIngredients;
  }

  const cardIngredients = markdownRecipeCardIngredients(lines);
  if (cardIngredients.length > 0) {
    return cardIngredients;
  }

  const cookModeIngredients = markdownIngredientsBeforeCookMode(lines);
  if (cookModeIngredients.length > 0) {
    return cookModeIngredients;
  }

  return markdownContiguousRecipeLists(lines).ingredients;
}

function markdownSteps(lines: string[]): string[] {
  const sectionSteps = markdownInstructionSection(lines);
  if (sectionSteps.length > 0) {
    return sectionSteps;
  }

  const afterIngredientsSteps = markdownStepsAfterIngredients(lines);
  if (afterIngredientsSteps.length > 0) {
    return afterIngredientsSteps;
  }

  const cardSteps = markdownRecipeCardSteps(lines);
  if (cardSteps.length > 0) {
    return cardSteps;
  }

  const cookModeSteps = markdownStepsAfterCookMode(lines);
  if (cookModeSteps.length > 0) {
    return cookModeSteps;
  }

  return markdownContiguousRecipeLists(lines).steps;
}

function markdownHeroImage(markdown: string): string | null {
  const match = markdown.match(/!\[[^\]]*]\((https?:\/\/[^\s]+(?:\([^)]*\)[^\s]*)?)\)/);
  return match ? cleanString(match[1], 1000) : null;
}

function markdownDescription(lines: string[]): string | null {
  return (
    lines
      .map((line) => cleanMarkdownText(line, 2000))
      .find((line) => {
        if (!line || line.length < 80) {
          return false;
        }
        const lower = line.toLowerCase();
        return (
          !lower.startsWith('url source:') &&
          !lower.startsWith('markdown content:') &&
          !lower.includes('http://') &&
          !lower.includes('https://') &&
          !line.startsWith('*') &&
          !line.startsWith('#')
        );
      }) ?? null
  );
}

function scrapeRecipeMarkdown(markdown: string): ScrapedRecipe {
  const lines = markdownLines(markdown);
  if (
    markdown.includes('Warning: Target URL returned error 403') ||
    markdown.includes('Verification successful. Waiting for') ||
    markdown.toLowerCase().includes('title: just a moment') ||
    lines.some((line) => /^(#\s+)?(just a moment|access denied)$/i.test(line))
  ) {
    throw new ApiError(
      502,
      'RECIPE_IMPORT_SITE_BLOCKED',
      'That recipe site blocked direct import. Try another recipe page.'
    );
  }

  const name = markdownHeadingTitle(lines);
  const recipeIngredients = markdownIngredients(lines);
  const recipeInstructions = markdownSteps(lines);

  if (!name || recipeIngredients.length === 0) {
    throw new ApiError(
      422,
      'RECIPE_IMPORT_NO_RECIPE_SCHEMA',
      'Could not find structured recipe data on that page'
    );
  }

  return {
    name,
    image: markdownHeroImage(markdown) ?? undefined,
    description: markdownDescription(lines) ?? undefined,
    prepTime: markdownValueAfterLabel(lines, 'Prep Time') ?? markdownValueAfterLabel(lines, 'Prep') ?? undefined,
    cookTime: markdownValueAfterLabel(lines, 'Cook Time') ?? markdownValueAfterLabel(lines, 'Cook') ?? undefined,
    totalTime: markdownValueAfterLabel(lines, 'Total Time') ?? undefined,
    recipeYield: markdownServings(lines) ?? undefined,
    recipeIngredients,
    recipeInstructions
  };
}

function shouldTryReaderFallback(error: unknown): boolean {
  return (
    error instanceof ApiError &&
    (error.code === 'RECIPE_IMPORT_SITE_BLOCKED' ||
      error.code === 'RECIPE_IMPORT_TIMEOUT' ||
      error.code === 'RECIPE_IMPORT_NO_RECIPE_SCHEMA' ||
      error.code === 'RECIPE_IMPORT_INCOMPLETE_RECIPE')
  );
}

async function scrapeRecipeHtml(html: string): Promise<ScrapedRecipe> {
  try {
    const scraped = (await getRecipeData({ html })) as ScrapedRecipe | undefined;
    if (!scraped) {
      throw new Error('No recipe found');
    }
    return scraped;
  } catch {
    throw new ApiError(
      422,
      'RECIPE_IMPORT_NO_RECIPE_SCHEMA',
      'Could not find structured recipe data on that page'
    );
  }
}

export function buildRecipeDraft(scraped: ScrapedRecipe, sourceUrl: string): RecipeDraft {
  const safeUrl = assertSafeRecipeUrl(sourceUrl);
  const title = cleanString(scraped.name, 180);
  const ingredients = compactStringList(scraped.recipeIngredients, 700).map((rawText) => ({
    rawText,
    quantityText: null,
    unitText: null,
    ingredientName: null
  }));
  const steps = compactStringList(scraped.recipeInstructions, 2000).map((text) => ({ text }));

  if (!title || ingredients.length === 0) {
    throw new ApiError(
      422,
      'RECIPE_IMPORT_INCOMPLETE_RECIPE',
      'Recipe data is missing a title or ingredients'
    );
  }

  const warnings: string[] = [];
  if (steps.length === 0) {
    warnings.push('No instructions were found. The user can add steps before saving.');
  }

  return {
    title,
    sourceUrl: safeUrl.url,
    sourceDomain: safeUrl.domain,
    sourceName: safeUrl.domain,
    heroImageUrl: cleanString(scraped.image, 1000),
    description: cleanString(scraped.description, 2000),
    servings: cleanString(scraped.recipeYield, 120),
    prepTime: cleanString(scraped.prepTime, 120),
    cookTime: cleanString(scraped.cookTime, 120),
    totalTime: cleanString(scraped.totalTime, 120),
    categories: compactStringList(scraped.recipeCategories, 80),
    cuisines: compactStringList(scraped.recipeCuisines, 80),
    keywords: compactStringList(scraped.keywords, 80),
    ingredients,
    steps,
    confidence: steps.length > 0 ? 0.92 : 0.78,
    warnings
  };
}

export async function importRecipeFromUrl(input: {
  userId: string;
  auth?: AuthContext;
  url: string;
}): Promise<{ importId: string; draft: RecipeDraft }> {
  const safeUrl = assertSafeRecipeUrl(input.url);
  const draft = await importRecipeDraftFromSafeUrl(safeUrl);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await ensureUserExists(input.userId, { authProvider: input.auth?.authProvider, email: input.auth?.userEmail }, client);
    const inserted = await client.query<{ id: string }>(
      `
      INSERT INTO recipe_imports (user_id, source_url, source_domain, status, draft_json)
      VALUES ($1, $2, $3, 'draft', $4::jsonb)
      RETURNING id
      `,
      [input.userId, draft.sourceUrl, draft.sourceDomain, JSON.stringify(draft)]
    );
    await client.query('COMMIT');
    return { importId: inserted.rows[0]!.id, draft };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function importRecipeDraftFromSafeUrl(safeUrl: SafeRecipeUrl): Promise<RecipeDraft> {
  try {
    const { finalUrl, html } = await fetchRecipeHtml(safeUrl.url);
    const scraped = await scrapeRecipeHtml(html);
    const draft = buildRecipeDraft(scraped, finalUrl);
    if (draft.ingredients.length > 60) {
      throw new ApiError(
        422,
        'RECIPE_IMPORT_INCOMPLETE_RECIPE',
        'Recipe data looked noisy, so reader fallback is required'
      );
    }
    return draft;
  } catch (error) {
    if (!shouldTryReaderFallback(error)) {
      throw error;
    }
    const { finalUrl, markdown } = await fetchRecipeMarkdownViaReader(safeUrl.url);
    const scraped = scrapeRecipeMarkdown(markdown);
    return buildRecipeDraft(scraped, finalUrl);
  }
}

export async function importRecipeDraftForSmokeTest(url: string): Promise<RecipeDraft> {
  return importRecipeDraftFromSafeUrl(assertSafeRecipeUrl(url));
}

function normalizeDraftForSave(input: SavedRecipeInput): Omit<SavedRecipeInput, 'sourceUrl'> & {
  sourceUrl: string;
  sourceDomain: string;
} {
  const safeUrl = assertSafeRecipeUrl(input.sourceUrl);
  const title = cleanString(input.title, 180);
  const ingredients = input.ingredients
    .map((ingredient) => ({
      rawText: cleanString(ingredient.rawText, 700),
      quantityText: cleanString(ingredient.quantityText, 120),
      unitText: cleanString(ingredient.unitText, 80),
      ingredientName: cleanString(ingredient.ingredientName, 220)
    }))
    .filter((ingredient): ingredient is RecipeIngredientDraft => Boolean(ingredient.rawText));
  const steps = input.steps
    .map((step) => ({ text: cleanString(step.text, 2000) }))
    .filter((step): step is RecipeStepDraft => Boolean(step.text));

  if (!title || ingredients.length === 0) {
    throw new ApiError(400, 'RECIPE_INVALID_REVIEW_DATA', 'Recipe needs a title and at least one ingredient');
  }

  return {
    ...input,
    title,
    sourceUrl: safeUrl.url,
    sourceDomain: safeUrl.domain,
    sourceName: cleanString(input.sourceName, 180),
    heroImageUrl: cleanString(input.heroImageUrl, 1000),
    description: cleanString(input.description, 2000),
    servings: cleanString(input.servings, 120),
    prepTime: cleanString(input.prepTime, 120),
    cookTime: cleanString(input.cookTime, 120),
    totalTime: cleanString(input.totalTime, 120),
    categories: compactStringList(input.categories, 80),
    cuisines: compactStringList(input.cuisines, 80),
    keywords: compactStringList(input.keywords, 80),
    ingredients,
    steps
  };
}

async function insertRecipeChildren(
  client: PoolClient,
  recipeId: string,
  ingredients: RecipeIngredientDraft[],
  steps: RecipeStepDraft[]
): Promise<void> {
  for (const [index, ingredient] of ingredients.entries()) {
    await client.query(
      `
      INSERT INTO recipe_ingredients (recipe_id, position, raw_text, quantity_text, unit_text, ingredient_name)
      VALUES ($1, $2, $3, $4, $5, $6)
      `,
      [
        recipeId,
        index,
        ingredient.rawText,
        ingredient.quantityText,
        ingredient.unitText,
        ingredient.ingredientName
      ]
    );
  }

  for (const [index, step] of steps.entries()) {
    await client.query(
      `
      INSERT INTO recipe_steps (recipe_id, position, text)
      VALUES ($1, $2, $3)
      `,
      [recipeId, index, step.text]
    );
  }
}

function parseIngredients(value: unknown): RecipeIngredientDraft[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((item) => {
      if (!item || typeof item !== 'object') {
        return null;
      }
      const record = item as Record<string, unknown>;
      const rawText = cleanString(record.rawText);
      if (!rawText) {
        return null;
      }
      return {
        rawText,
        quantityText: cleanString(record.quantityText, 120),
        unitText: cleanString(record.unitText, 80),
        ingredientName: cleanString(record.ingredientName, 220)
      };
    })
    .filter((item): item is RecipeIngredientDraft => Boolean(item));
}

function parseSteps(value: unknown): RecipeStepDraft[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((item) => {
      if (!item || typeof item !== 'object') {
        return null;
      }
      const text = cleanString((item as Record<string, unknown>).text, 2000);
      return text ? { text } : null;
    })
    .filter((item): item is RecipeStepDraft => Boolean(item));
}

function toSavedRecipe(row: RecipeRow): SavedRecipe {
  return {
    id: row.id,
    importId: row.import_id,
    title: row.title,
    sourceUrl: row.source_url,
    sourceDomain: row.source_domain,
    sourceName: row.source_name,
    heroImageUrl: row.hero_image_url,
    description: row.description,
    servings: row.servings,
    prepTime: row.prep_time,
    cookTime: row.cook_time,
    totalTime: row.total_time,
    categories: row.categories ?? [],
    cuisines: row.cuisines ?? [],
    keywords: row.keywords ?? [],
    ingredients: parseIngredients(row.ingredients),
    steps: parseSteps(row.steps),
    nutrition: row.nutrition_json,
    createdAt: row.created_at.toISOString(),
    updatedAt: row.updated_at.toISOString()
  };
}

const recipeSelectSql = `
  SELECT
    r.id,
    r.import_id,
    r.title,
    r.source_url,
    r.source_domain,
    r.source_name,
    r.hero_image_url,
    r.description,
    r.servings,
    r.prep_time,
    r.cook_time,
    r.total_time,
    r.categories,
    r.cuisines,
    r.keywords,
    r.nutrition_json,
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'rawText', ri.raw_text,
          'quantityText', ri.quantity_text,
          'unitText', ri.unit_text,
          'ingredientName', ri.ingredient_name
        )
        ORDER BY ri.position
      )
      FROM recipe_ingredients ri
      WHERE ri.recipe_id = r.id
    ), '[]'::jsonb) AS ingredients,
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object('text', rs.text)
        ORDER BY rs.position
      )
      FROM recipe_steps rs
      WHERE rs.recipe_id = r.id
    ), '[]'::jsonb) AS steps,
    r.created_at,
    r.updated_at
  FROM recipes r
`;

export async function saveRecipe(input: {
  userId: string;
  auth?: AuthContext;
  recipe: SavedRecipeInput;
}): Promise<SavedRecipe> {
  const recipe = normalizeDraftForSave(input.recipe);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await ensureUserExists(input.userId, { authProvider: input.auth?.authProvider, email: input.auth?.userEmail }, client);

    if (recipe.importId) {
      const importResult = await client.query<{ id: string }>(
        `SELECT id FROM recipe_imports WHERE id = $1 AND user_id = $2`,
        [recipe.importId, input.userId]
      );
      if (!importResult.rows[0]) {
        throw new ApiError(404, 'RECIPE_IMPORT_NOT_FOUND', 'Recipe import not found');
      }
    }

    const inserted = await client.query<{ id: string }>(
      `
      INSERT INTO recipes (
        user_id, import_id, title, source_url, source_domain, source_name, hero_image_url,
        description, servings, prep_time, cook_time, total_time, categories, cuisines,
        keywords, nutrition_json
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16::jsonb)
      RETURNING id
      `,
      [
        input.userId,
        recipe.importId ?? null,
        recipe.title,
        recipe.sourceUrl,
        recipe.sourceDomain,
        recipe.sourceName,
        recipe.heroImageUrl,
        recipe.description,
        recipe.servings,
        recipe.prepTime,
        recipe.cookTime,
        recipe.totalTime,
        recipe.categories,
        recipe.cuisines,
        recipe.keywords,
        recipe.nutrition === undefined ? null : JSON.stringify(recipe.nutrition)
      ]
    );

    const recipeId = inserted.rows[0]!.id;
    await insertRecipeChildren(client, recipeId, recipe.ingredients, recipe.steps);

    if (recipe.importId) {
      await client.query(
        `
        UPDATE recipe_imports
        SET status = 'saved', updated_at = NOW()
        WHERE id = $1 AND user_id = $2
        `,
        [recipe.importId, input.userId]
      );
    }

    const saved = await client.query<RecipeRow>(
      `${recipeSelectSql} WHERE r.id = $1 AND r.user_id = $2`,
      [recipeId, input.userId]
    );
    await client.query('COMMIT');
    return toSavedRecipe(saved.rows[0]!);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function listRecipes(userId: string): Promise<{ recipes: SavedRecipe[] }> {
  const result = await pool.query<RecipeRow>(
    `${recipeSelectSql} WHERE r.user_id = $1 ORDER BY r.updated_at DESC, r.created_at DESC`,
    [userId]
  );
  return { recipes: result.rows.map(toSavedRecipe) };
}
