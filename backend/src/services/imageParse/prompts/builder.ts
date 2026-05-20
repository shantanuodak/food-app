import { SHARED_PROMPT_HEADER } from './shared/header.js';
import { INDIAN_PROMPT } from './cuisines/indian.js';
import { US_PROMPT } from './cuisines/us.js';
import { WESTERN_PROMPT } from './cuisines/western.js';
import { EAST_ASIAN_PROMPT } from './cuisines/eastAsian.js';
import { MEDITERRANEAN_PROMPT } from './cuisines/mediterranean.js';
import { LATIN_PROMPT } from './cuisines/latin.js';
import { GENERIC_PROMPT } from './cuisines/generic.js';
import type { Cuisine } from '../cuisineClassifier.js';

const CUISINE_PROMPTS: Record<Cuisine, string> = {
  indian: INDIAN_PROMPT,
  us: US_PROMPT,
  western: WESTERN_PROMPT,
  eastAsian: EAST_ASIAN_PROMPT,
  mediterranean: MEDITERRANEAN_PROMPT,
  latin: LATIN_PROMPT,
  generic: GENERIC_PROMPT
};

export function buildCuisinePrompt(args: { cuisine: Cuisine; contextNote?: string }): string {
  const context = args.contextNote?.trim()
    ? `\n\nUSER NOTE: "${args.contextNote.trim()}"\nUse this only when compatible with the image.`
    : '';
  return `${SHARED_PROMPT_HEADER}\n\n${CUISINE_PROMPTS[args.cuisine]}${context}`;
}
