import 'dotenv/config';
/**
 * Live before/after eval for the LLM cleanup pass.
 *
 * Scores a set of recipe drafts, runs each through the REAL Gemini cleanup
 * pass (recipeCleanupService), re-scores, and prints the delta. Fixtures
 * span the defect types the baseline surfaced:
 *   - prose-blob steps + junk ingredient lines + clickbait title
 *   - social-caption noise (hashtags, emoji, follow-me CTAs)
 *   - junk-heavy web scrape (nav/nutrition lines, site-suffix title)
 *   - an already-clean recipe (proves cleanup does NOT harm clean input —
 *     it should hold or improve, never regress)
 *
 * Usage: npm run recipe:clean-eval
 * Requires GEMINI_API_KEY in backend/.env.
 */

import { cleanupRecipeDraft } from '../services/recipeCleanupService.js';
import { scoreRecipeDraft } from '../services/recipeQualityScore.js';
import type { RecipeDraft } from '../services/recipeImportService.js';

function draft(partial: Partial<RecipeDraft> & Pick<RecipeDraft, 'title' | 'ingredients' | 'steps'>): RecipeDraft {
  return {
    sourceUrl: 'https://example.com/r',
    sourceDomain: 'example.com',
    sourceName: 'Example',
    heroImageUrl: 'https://example.com/img.jpg',
    description: null,
    servings: '4 servings',
    prepTime: '10 mins',
    cookTime: '20 mins',
    totalTime: '30 mins',
    categories: [],
    cuisines: [],
    keywords: [],
    confidence: 0.8,
    warnings: [],
    ...partial,
  };
}

function ing(rawText: string): RecipeDraft['ingredients'][number] {
  return { rawText, quantityText: null, unitText: null, ingredientName: null };
}

const FIXTURES: { name: string; draft: RecipeDraft }[] = [
  {
    name: 'prose-blob + junk + clickbait title',
    draft: draft({
      title: 'The BEST Ever Creamy Garlic Pasta!! | FoodBlog',
      description: 'Hands down the best pasta you will ever make, trust me, keep reading!',
      ingredients: [
        ing('8 oz spaghetti'), ing('4 cloves garlic minced'), ing('2 tbsp butter'),
        ing('1 cup heavy cream'), ing('Jump to Recipe'), ing('Calories 520 kcal Protein 12g Fat 28g'),
      ],
      steps: [{ text: 'Cook the spaghetti in salted boiling water until al dente then in a pan melt the butter and add the garlic cooking until fragrant before pouring in the cream and simmering until thickened then toss the drained pasta in the sauce and season to taste and serve immediately with parmesan on top.' }],
    }),
  },
  {
    name: 'social-caption noise',
    draft: draft({
      title: '🔥 VIRAL Tiktok Pasta 🔥 #pasta #foodie #viral',
      description: 'omg you guys this BROKE the internet 😭 follow for more!!',
      heroImageUrl: null,
      servings: null, prepTime: null, cookTime: null, totalTime: null,
      ingredients: [
        ing('1 box of pasta'), ing('cherry tomatoes a whole container'), ing('1 block feta'),
        ing('olive oil just pour it'), ing('garlic'), ing('LIKE & SUBSCRIBE for part 2 🔔'),
      ],
      steps: [{ text: 'ok so basically dump everything in a dish and bake at 400 then mix it all up and add pasta its SO good trust 🤤 comment if you try it!! #fyp' }],
    }),
  },
  {
    name: 'junk-heavy web scrape',
    draft: draft({
      title: 'Easy Sheet Pan Chicken and Veggies Recipe - Delish.com',
      ingredients: [
        ing('Advertisement'), ing('1.5 lb chicken thighs'), ing('2 cups broccoli florets'),
        ing('3 tbsp olive oil'), ing('Print Recipe'), ing('1 tsp paprika'),
        ing('Salt and pepper to taste'), ing('Nutrition Facts Per Serving'), ing('Calories: 410'),
      ],
      steps: [
        { text: 'Preheat oven to 425°F.' },
        { text: 'Jump to Recipe' },
        { text: 'Toss the chicken and broccoli with oil and spices.' },
        { text: 'Roast for 25 minutes until cooked through.' },
        { text: 'As an Amazon Associate I earn from qualifying purchases.' },
      ],
    }),
  },
  {
    name: 'already-clean (no-harm check)',
    draft: draft({
      title: 'Weeknight Chicken Stir-Fry',
      description: 'A fast, balanced stir-fry.',
      ingredients: [
        ing('1 lb boneless chicken thighs, sliced'), ing('2 tbsp soy sauce'), ing('1 tbsp sesame oil'),
        ing('3 cloves garlic, minced'), ing('2 cups broccoli florets'), ing('Salt and pepper to taste'),
      ],
      steps: [
        { text: 'Heat the sesame oil in a large skillet over medium-high heat.' },
        { text: 'Add the chicken and cook until browned, about 5 minutes.' },
        { text: 'Stir in the garlic and broccoli and cook for 4 minutes.' },
        { text: 'Pour in the soy sauce, toss to coat, and serve hot.' },
      ],
    }),
  },
];

async function main() {
  console.log('Live cleanup eval (real Gemini)\n');
  console.log('  BEFORE  AFTER   Δ   | RESOLVED DEFECTS                 | FIXTURE');
  console.log('  ' + '─'.repeat(82));

  const deltas: number[] = [];
  let regressions = 0;

  for (const { name, draft: d } of FIXTURES) {
    const before = scoreRecipeDraft(d);
    const { cleaned, changed, skippedReason, usage } = await cleanupRecipeDraft(d);
    const after = scoreRecipeDraft(cleaned);
    const delta = after.overall - before.overall;
    deltas.push(delta);
    if (delta < 0) regressions += 1;

    const beforeCodes = new Set(before.defects.map((x) => x.code));
    const afterCodes = new Set(after.defects.map((x) => x.code));
    const resolved = [...beforeCodes].filter((c) => !afterCodes.has(c));
    const introduced = [...afterCodes].filter((c) => !beforeCodes.has(c));

    const deltaStr = (delta >= 0 ? '+' : '') + delta;
    const status = changed ? '' : ` [SKIPPED:${skippedReason}]`;
    console.log(
      `  ${String(before.overall).padStart(4)}   ${String(after.overall).padStart(4)}  ${deltaStr.padStart(4)}  | ` +
      `${resolved.join(', ').slice(0, 30).padEnd(31)} | ${name}${status}`
    );
    if (introduced.length) console.log(`         ⚠ introduced: ${introduced.join(', ')}`);
    if (usage) console.log(`         (${usage.inputTokens}→${usage.outputTokens} tok)`);
  }

  const mean = deltas.reduce((a, b) => a + b, 0) / deltas.length;
  console.log('  ' + '─'.repeat(82));
  console.log(`\nMean score delta: ${mean >= 0 ? '+' : ''}${mean.toFixed(1)}   regressions: ${regressions}/${deltas.length}`);
}

main().catch((err) => { console.error('Eval crashed:', err); process.exit(1); });
