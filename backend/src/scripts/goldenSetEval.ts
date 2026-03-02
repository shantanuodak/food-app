import { runPrimaryParsePipeline } from '../services/parsePipelineService.js';

type GoldenCase = {
  cuisine: string;
  text: string;
  expectedKeywords: string[];
  caloriesRange?: { min: number; max: number };
};

const GOLDEN_CASES: GoldenCase[] = [
  {
    cuisine: 'American',
    text: 'Black Coffee 1 Cup',
    expectedKeywords: ['coffee'],
    caloriesRange: { min: 0, max: 15 }
  },
  {
    cuisine: 'American',
    text: 'Coke 8oz',
    expectedKeywords: ['coke', 'cola', 'soft drink', 'soda'],
    caloriesRange: { min: 60, max: 120 }
  },
  {
    cuisine: 'American',
    text: 'Cheeseburger 1 burger',
    expectedKeywords: ['cheeseburger', 'burger'],
    caloriesRange: { min: 250, max: 900 }
  },
  {
    cuisine: 'American',
    text: 'Pepperoni Pizza 2 slices',
    expectedKeywords: ['pizza', 'pepperoni'],
    caloriesRange: { min: 300, max: 900 }
  },
  {
    cuisine: 'American',
    text: 'Caesar Salad with Chicken',
    expectedKeywords: ['caesar', 'salad', 'chicken'],
    caloriesRange: { min: 180, max: 800 }
  },
  {
    cuisine: 'American',
    text: 'Buffalo Wings 6 pieces',
    expectedKeywords: ['wing', 'buffalo'],
    caloriesRange: { min: 250, max: 1000 }
  },
  {
    cuisine: 'American',
    text: 'Chocolate Milkshake 12 oz',
    expectedKeywords: ['milkshake', 'chocolate'],
    caloriesRange: { min: 180, max: 800 }
  },
  {
    cuisine: 'Indian',
    text: 'Chicken Tikka Masala 1 cup',
    expectedKeywords: ['chicken', 'tikka', 'masala'],
    caloriesRange: { min: 180, max: 750 }
  },
  {
    cuisine: 'Indian',
    text: 'Dal Tadka 1 bowl',
    expectedKeywords: ['dal', 'lentil', 'tadka'],
    caloriesRange: { min: 120, max: 550 }
  },
  {
    cuisine: 'Indian',
    text: 'Chole Bhature 1 plate',
    expectedKeywords: ['chole', 'bhature', 'chickpea'],
    caloriesRange: { min: 350, max: 1300 }
  },
  {
    cuisine: 'Indian',
    text: 'Pav Bhaji 1 plate',
    expectedKeywords: ['pav', 'bhaji'],
    caloriesRange: { min: 180, max: 900 }
  },
  {
    cuisine: 'Indian',
    text: 'Samosa 2 pieces',
    expectedKeywords: ['samosa'],
    caloriesRange: { min: 140, max: 700 }
  },
  {
    cuisine: 'Indian',
    text: 'Aloo Paratha with Butter',
    expectedKeywords: ['aloo', 'paratha'],
    caloriesRange: { min: 220, max: 900 }
  },
  {
    cuisine: 'Indian',
    text: 'Idli 3 pieces with Sambar',
    expectedKeywords: ['idli', 'sambar'],
    caloriesRange: { min: 120, max: 700 }
  },
  {
    cuisine: 'Indian',
    text: 'Masala Dosa 1 dosa',
    expectedKeywords: ['dosa', 'masala'],
    caloriesRange: { min: 180, max: 850 }
  },
  {
    cuisine: 'Indian',
    text: 'Rajma Chawal 1 bowl',
    expectedKeywords: ['rajma', 'rice', 'chawal'],
    caloriesRange: { min: 220, max: 900 }
  },
  {
    cuisine: 'Indian',
    text: 'Palak Paneer 1 cup',
    expectedKeywords: ['palak', 'paneer'],
    caloriesRange: { min: 160, max: 700 }
  },
  {
    cuisine: 'Italian',
    text: 'Spaghetti Bolognese 1 plate',
    expectedKeywords: ['spaghetti', 'bolognese', 'pasta'],
    caloriesRange: { min: 220, max: 1100 }
  },
  {
    cuisine: 'Italian',
    text: 'Penne Alfredo 1 bowl',
    expectedKeywords: ['penne', 'alfredo', 'pasta'],
    caloriesRange: { min: 250, max: 1200 }
  },
  {
    cuisine: 'Italian',
    text: 'Margherita Pizza 3 slices',
    expectedKeywords: ['pizza', 'margherita'],
    caloriesRange: { min: 250, max: 1100 }
  },
  {
    cuisine: 'Italian',
    text: 'Lasagna 1 serving',
    expectedKeywords: ['lasagna'],
    caloriesRange: { min: 220, max: 1000 }
  },
  {
    cuisine: 'Italian',
    text: 'Minestrone Soup 1 bowl',
    expectedKeywords: ['minestrone', 'soup'],
    caloriesRange: { min: 70, max: 450 }
  },
  {
    cuisine: 'Italian',
    text: 'Risotto Mushroom 1 cup',
    expectedKeywords: ['risotto', 'mushroom'],
    caloriesRange: { min: 180, max: 800 }
  },
  {
    cuisine: 'Italian',
    text: 'Tiramisu 1 slice',
    expectedKeywords: ['tiramisu'],
    caloriesRange: { min: 180, max: 700 }
  },
  {
    cuisine: 'Mexican',
    text: 'Chicken Burrito 1 burrito',
    expectedKeywords: ['burrito', 'chicken'],
    caloriesRange: { min: 250, max: 1200 }
  },
  {
    cuisine: 'Mexican',
    text: 'Beef Tacos 3 tacos',
    expectedKeywords: ['taco', 'beef'],
    caloriesRange: { min: 220, max: 1200 }
  },
  {
    cuisine: 'Mexican',
    text: 'Quesadilla Cheese 1 piece',
    expectedKeywords: ['quesadilla', 'cheese'],
    caloriesRange: { min: 180, max: 900 }
  },
  {
    cuisine: 'Mexican',
    text: 'Nachos with Salsa',
    expectedKeywords: ['nachos', 'salsa'],
    caloriesRange: { min: 140, max: 1000 }
  },
  {
    cuisine: 'Mexican',
    text: 'Chicken Fajitas 1 plate',
    expectedKeywords: ['fajita', 'chicken'],
    caloriesRange: { min: 180, max: 1000 }
  },
  {
    cuisine: 'Mexican',
    text: 'Guacamole 1 cup',
    expectedKeywords: ['guacamole', 'avocado'],
    caloriesRange: { min: 120, max: 700 }
  },
  {
    cuisine: 'Chinese',
    text: 'Kung Pao Chicken 1 bowl',
    expectedKeywords: ['kung pao', 'chicken'],
    caloriesRange: { min: 200, max: 950 }
  },
  {
    cuisine: 'Chinese',
    text: 'Vegetable Fried Rice 1 bowl',
    expectedKeywords: ['fried rice', 'vegetable', 'rice'],
    caloriesRange: { min: 180, max: 950 }
  },
  {
    cuisine: 'Chinese',
    text: 'Chow Mein 1 plate',
    expectedKeywords: ['chow mein', 'noodle'],
    caloriesRange: { min: 180, max: 950 }
  },
  {
    cuisine: 'Chinese',
    text: 'Sweet and Sour Pork 1 serving',
    expectedKeywords: ['sweet', 'sour', 'pork'],
    caloriesRange: { min: 220, max: 950 }
  },
  {
    cuisine: 'Chinese',
    text: 'Dim Sum 6 pieces',
    expectedKeywords: ['dim sum', 'dumpling'],
    caloriesRange: { min: 150, max: 900 }
  },
  {
    cuisine: 'Chinese',
    text: 'Hot and Sour Soup 1 bowl',
    expectedKeywords: ['hot', 'sour', 'soup'],
    caloriesRange: { min: 70, max: 450 }
  },
  {
    cuisine: 'Japanese',
    text: 'Salmon Sushi 8 pieces',
    expectedKeywords: ['salmon', 'sushi'],
    caloriesRange: { min: 180, max: 700 }
  },
  {
    cuisine: 'Japanese',
    text: 'Chicken Teriyaki with Rice',
    expectedKeywords: ['teriyaki', 'chicken', 'rice'],
    caloriesRange: { min: 220, max: 1000 }
  },
  {
    cuisine: 'Japanese',
    text: 'Ramen Tonkotsu 1 bowl',
    expectedKeywords: ['ramen', 'tonkotsu'],
    caloriesRange: { min: 250, max: 1200 }
  },
  {
    cuisine: 'Japanese',
    text: 'Miso Soup 1 cup',
    expectedKeywords: ['miso', 'soup'],
    caloriesRange: { min: 20, max: 250 }
  },
  {
    cuisine: 'Japanese',
    text: 'Tempura Shrimp 5 pieces',
    expectedKeywords: ['tempura', 'shrimp'],
    caloriesRange: { min: 160, max: 900 }
  },
  {
    cuisine: 'Middle Eastern',
    text: 'Chicken Shawarma Wrap',
    expectedKeywords: ['shawarma', 'chicken', 'wrap'],
    caloriesRange: { min: 220, max: 950 }
  },
  {
    cuisine: 'Middle Eastern',
    text: 'Falafel 6 pieces',
    expectedKeywords: ['falafel'],
    caloriesRange: { min: 180, max: 900 }
  },
  {
    cuisine: 'Middle Eastern',
    text: 'Hummus 1 cup with Pita',
    expectedKeywords: ['hummus', 'pita'],
    caloriesRange: { min: 180, max: 1000 }
  },
  {
    cuisine: 'Middle Eastern',
    text: 'Lamb Kebab 2 skewers',
    expectedKeywords: ['lamb', 'kebab'],
    caloriesRange: { min: 220, max: 1000 }
  },
  {
    cuisine: 'Middle Eastern',
    text: 'Tabbouleh Salad 1 bowl',
    expectedKeywords: ['tabbouleh', 'salad'],
    caloriesRange: { min: 80, max: 500 }
  },
  {
    cuisine: 'Thai',
    text: 'Pad Thai Shrimp 1 plate',
    expectedKeywords: ['pad thai', 'shrimp'],
    caloriesRange: { min: 220, max: 1100 }
  },
  {
    cuisine: 'Thai',
    text: 'Green Curry Chicken 1 bowl',
    expectedKeywords: ['green curry', 'chicken'],
    caloriesRange: { min: 220, max: 1000 }
  },
  {
    cuisine: 'Thai',
    text: 'Tom Yum Soup 1 bowl',
    expectedKeywords: ['tom yum', 'soup'],
    caloriesRange: { min: 50, max: 450 }
  },
  {
    cuisine: 'Vietnamese',
    text: 'Pho Beef 1 bowl',
    expectedKeywords: ['pho', 'beef', 'noodle'],
    caloriesRange: { min: 180, max: 900 }
  },
  {
    cuisine: 'Vietnamese',
    text: 'Spring Rolls 2 rolls',
    expectedKeywords: ['spring roll'],
    caloriesRange: { min: 120, max: 700 }
  },
  {
    cuisine: 'Korean',
    text: 'Bibimbap 1 bowl',
    expectedKeywords: ['bibimbap', 'rice'],
    caloriesRange: { min: 220, max: 1000 }
  },
  {
    cuisine: 'Korean',
    text: 'Kimchi Fried Rice 1 bowl',
    expectedKeywords: ['kimchi', 'fried rice'],
    caloriesRange: { min: 180, max: 950 }
  },
  {
    cuisine: 'Korean',
    text: 'Bulgogi Beef 1 serving',
    expectedKeywords: ['bulgogi', 'beef'],
    caloriesRange: { min: 180, max: 900 }
  },
  {
    cuisine: 'Mediterranean',
    text: 'Greek Salad with Feta',
    expectedKeywords: ['greek', 'salad', 'feta'],
    caloriesRange: { min: 120, max: 700 }
  },
  {
    cuisine: 'Mediterranean',
    text: 'Avocado Toast 2 slices',
    expectedKeywords: ['avocado', 'toast'],
    caloriesRange: { min: 180, max: 800 }
  },
  {
    cuisine: 'Dessert',
    text: 'Vanilla Ice Cream 1 scoop',
    expectedKeywords: ['vanilla', 'ice cream'],
    caloriesRange: { min: 80, max: 450 }
  },
  {
    cuisine: 'Dessert',
    text: 'Brownie 1 piece',
    expectedKeywords: ['brownie'],
    caloriesRange: { min: 120, max: 650 }
  },
  {
    cuisine: 'Dessert',
    text: 'Banana Pudding 1 cup',
    expectedKeywords: ['banana', 'pudding'],
    caloriesRange: { min: 120, max: 700 }
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
    cuisine: string;
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
      cuisine: testCase.cuisine,
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
  const cuisineCounts = rows.reduce<Record<string, number>>((acc, row) => {
    acc[row.cuisine] = (acc[row.cuisine] || 0) + 1;
    return acc;
  }, {});

  console.log('Golden Set Efficacy Report');
  console.log('==========================');
  for (const row of rows) {
    console.log(`\nCuisine: ${row.cuisine}`);
    console.log(`Input: ${row.text}`);
    console.log(`Route: ${row.route}`);
    console.log(`Items: ${row.names || '(none)'}`);
    console.log(`Total Calories: ${row.totalCalories.toFixed(1)}`);
    console.log(`Keyword Check: ${row.passKeywords ? 'PASS' : 'FAIL'}`);
    console.log(`Calorie Range Check: ${row.passCalories ? 'PASS' : 'FAIL'}`);
  }
  console.log('\nSummary');
  console.log(`Passed: ${passed}/${rows.length}`);
  console.log(`Failed: ${rows.length - passed}/${rows.length}`);
  console.log(`Cuisine coverage: ${JSON.stringify(cuisineCounts)}`);
  console.log(`Routes: ${JSON.stringify(routeCounts)}`);
}

main().catch((err) => {
  console.error('Golden set eval failed', err);
  process.exitCode = 1;
});
