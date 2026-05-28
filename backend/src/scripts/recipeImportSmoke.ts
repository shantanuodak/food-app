import { pool } from '../db.js';
import { importRecipeDraftForSmokeTest } from '../services/recipeImportService.js';

type SmokeExpectation = 'import' | 'blocked';

type SmokeCase = {
  url: string;
  expectation: SmokeExpectation;
};

const defaultCases: SmokeCase[] = [
  { url: 'https://www.allrecipes.com/recipe/39748/actually-delicious-turkey-burgers/', expectation: 'import' },
  { url: 'https://www.loveandlemons.com/stir-fry-recipe/', expectation: 'import' },
  { url: 'https://www.foodnetwork.com/recipes/food-network-kitchen/chicken-parmesan-recipe-1953649', expectation: 'import' },
  { url: 'https://www.bbcgoodfood.com/recipes/best-ever-chocolate-brownies-recipe', expectation: 'import' },
  { url: 'https://www.seriouseats.com/the-best-slow-cooked-bolognese-sauce-recipe', expectation: 'import' },
  { url: 'https://cookieandkate.com/best-lentil-soup-recipe/', expectation: 'import' },
  { url: 'https://minimalistbaker.com/easy-vegan-ramen/', expectation: 'import' },
  { url: 'https://www.recipetineats.com/chicken-stir-fry/', expectation: 'import' },
  { url: 'https://www.gimmesomeoven.com/baked-chicken-breast/', expectation: 'blocked' },
  { url: 'https://sallysbakingaddiction.com/chewy-chocolate-chip-cookies/', expectation: 'import' },
  { url: 'https://www.eatingwell.com/recipe/267768/chicken-spinach-skillet-pasta-with-lemon-parmesan/', expectation: 'blocked' },
  { url: 'https://www.thekitchn.com/quiche-recipe-23649844', expectation: 'import' },
  { url: 'https://theicn.org/cnrb/recipes-for-schools/breakfast-bowl-usda-recipe-for-schools/', expectation: 'import' }
];

type SmokeResult = {
  url: string;
  expectation: SmokeExpectation;
  ok: boolean;
  title?: string;
  ingredients?: number;
  steps?: number;
  sourceDomain?: string;
  errorCode?: string;
  error?: string;
};

function casesFromArgs(): SmokeCase[] {
  const args = process.argv.slice(2).map((arg) => arg.trim()).filter(Boolean);
  return args.length > 0 ? args.map((url) => ({ url, expectation: 'import' })) : defaultCases;
}

function errorCodeFor(error: unknown): string | undefined {
  if (!error || typeof error !== 'object' || !('code' in error)) {
    return undefined;
  }
  return String((error as { code?: unknown }).code ?? '');
}

function domainFor(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return 'unknown-domain';
  }
}

function isExpectedBlocked(result: SmokeResult): boolean {
  return result.expectation === 'blocked' && result.errorCode === 'RECIPE_IMPORT_SITE_BLOCKED';
}

function resultHandled(result: SmokeResult): boolean {
  return result.ok || isExpectedBlocked(result);
}

async function smokeOne(testCase: SmokeCase): Promise<SmokeResult> {
  try {
    const draft = await importRecipeDraftForSmokeTest(testCase.url);
    return {
      url: testCase.url,
      expectation: testCase.expectation,
      ok: true,
      title: draft.title,
      sourceDomain: draft.sourceDomain,
      ingredients: draft.ingredients.length,
      steps: draft.steps.length
    };
  } catch (error) {
    return {
      url: testCase.url,
      expectation: testCase.expectation,
      ok: false,
      errorCode: errorCodeFor(error),
      error: error instanceof Error ? error.message : String(error)
    };
  }
}

function printResult(result: SmokeResult): void {
  if (result.ok) {
    console.log(
      [
        'PASS',
        result.sourceDomain,
        JSON.stringify(result.title),
        `${result.ingredients ?? 0} ingredients`,
        `${result.steps ?? 0} steps`,
        result.url
      ].join(' | ')
    );
    return;
  }

  if (isExpectedBlocked(result)) {
    console.log(['HANDLED', domainFor(result.url), result.errorCode, result.error, result.url].join(' | '));
    return;
  }

  console.log(['FAIL', result.error, result.url].join(' | '));
}

async function main(): Promise<void> {
  const cases = casesFromArgs();
  const results: SmokeResult[] = [];

  for (const testCase of cases) {
    const result = await smokeOne(testCase);
    results.push(result);
    printResult(result);
  }

  const failed = results.filter((result) => !resultHandled(result));
  console.log(`\nRecipe smoke: ${results.length - failed.length}/${results.length} handled`);
  if (failed.length > 0) {
    process.exitCode = 1;
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
