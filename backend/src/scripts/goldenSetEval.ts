import { runPrimaryParsePipeline } from '../services/parsePipelineService.js';

type GoldenCase = {
  text: string;
  expectedKeywords: string[];
  caloriesRange?: { min: number; max: number };
};

const GOLDEN_CASES: GoldenCase[] = [
  {
    text: 'Black Coffee 1 Cup',
    expectedKeywords: ['coffee'],
    caloriesRange: { min: 0, max: 15 }
  },
  {
    text: 'Coke 8oz',
    expectedKeywords: ['coke', 'cola', 'soft drink', 'soda'],
    caloriesRange: { min: 60, max: 120 }
  },
  {
    text: 'Milkshake',
    expectedKeywords: ['milkshake'],
    caloriesRange: { min: 120, max: 600 }
  },
  {
    text: 'Chicken Tikka And Naan',
    expectedKeywords: ['chicken', 'tikka', 'naan'],
    caloriesRange: { min: 200, max: 900 }
  },
  {
    text: 'Dairy Milk Bar',
    expectedKeywords: ['chocolate', 'milk bar', 'dairy milk'],
    caloriesRange: { min: 120, max: 400 }
  }
];

function normalize(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
}

function includesAnyKeyword(resultNames: string, keywords: string[]): boolean {
  return keywords.some((keyword) => resultNames.includes(normalize(keyword)));
}

async function main(): Promise<void> {
  const rows: Array<{
    text: string;
    route: string;
    totalCalories: number;
    names: string;
    passKeywords: boolean;
    passCalories: boolean;
  }> = [];

  for (const testCase of GOLDEN_CASES) {
    const output = await runPrimaryParsePipeline(testCase.text, { allowFallback: true });
    const names = output.result.items.map((item) => item.name).join(' | ');
    const normalizedNames = normalize(names);
    const totalCalories = output.result.totals.calories;
    const passKeywords = includesAnyKeyword(normalizedNames, testCase.expectedKeywords);
    const passCalories = testCase.caloriesRange
      ? totalCalories >= testCase.caloriesRange.min && totalCalories <= testCase.caloriesRange.max
      : true;

    rows.push({
      text: testCase.text,
      route: output.route,
      totalCalories,
      names,
      passKeywords,
      passCalories
    });
  }

  const passed = rows.filter((row) => row.passKeywords && row.passCalories).length;
  const routeCounts = rows.reduce<Record<string, number>>((acc, row) => {
    acc[row.route] = (acc[row.route] || 0) + 1;
    return acc;
  }, {});

  console.log('Golden Set Efficacy Report');
  console.log('==========================');
  for (const row of rows) {
    console.log(`\nInput: ${row.text}`);
    console.log(`Route: ${row.route}`);
    console.log(`Items: ${row.names || '(none)'}`);
    console.log(`Total Calories: ${row.totalCalories.toFixed(1)}`);
    console.log(`Keyword Check: ${row.passKeywords ? 'PASS' : 'FAIL'}`);
    console.log(`Calorie Range Check: ${row.passCalories ? 'PASS' : 'FAIL'}`);
  }
  console.log('\nSummary');
  console.log(`Passed: ${passed}/${rows.length}`);
  console.log(`Failed: ${rows.length - passed}/${rows.length}`);
  console.log(`Routes: ${JSON.stringify(routeCounts)}`);
}

main().catch((err) => {
  console.error('Golden set eval failed', err);
  process.exitCode = 1;
});

