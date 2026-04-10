/**
 * Curated golden set for parse pipeline accuracy evaluation.
 *
 * Ground truth values are hand-entered from authoritative sources, cited in `notes`.
 * No scraping, no LLM-generated values.
 *
 * Sources by category:
 *  - generic:        USDA FoodData Central (fdc.nal.usda.gov)
 *  - branded:        Manufacturer nutrition label (website or physical panel)
 *  - restaurant:     Official chain nutrition page (PDF or web)
 *  - international:  USDA composite entries or one consistent published reference recipe
 *  - tricky-portion: USDA generic × calculated portion math
 *  - misspelling:    Same values as the correctly-spelled intent
 *  - multi-item:     Sum of USDA generic components
 *
 * Caveat for international dishes: there is no single "correct" value —
 * real-world biryani/pad thai/ramen vary 30%+ by region and recipe.
 * The expected values are reference points, not scientific ground truth.
 */

export type EvalCategory =
  | 'generic'
  | 'branded'
  | 'restaurant'
  | 'international'
  | 'tricky-portion'
  | 'misspelling'
  | 'multi-item';

export type EvalExpected = {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
};

/** Fractional tolerance per macro (e.g. 0.15 = ±15%). */
export type EvalTolerance = Partial<EvalExpected>;

export type EvalCase = {
  id: string;
  category: EvalCategory;
  input: string;
  expected: EvalExpected;
  tolerance?: EvalTolerance;
  notes?: string;
};

/** Default tolerance applied when a case does not specify its own. */
export const DEFAULT_TOLERANCE = 0.15;

export const EVAL_GOLDEN_SET: EvalCase[] = [
  // ============================================================
  // GENERIC (8) — Gemini should nail these. Sanity baseline.
  // ============================================================
  {
    id: 'gen-001',
    category: 'generic',
    input: '2 eggs',
    expected: { calories: 144, protein: 12.6, carbs: 0.7, fat: 9.5 },
    notes: 'USDA FDC 748967 — Egg, whole, raw, large (50g). 2 × (72 kcal / 6.3g P / 0.36g C / 4.76g F).'
  },
  {
    id: 'gen-002',
    category: 'generic',
    input: '1 cup white rice cooked',
    expected: { calories: 205, protein: 4.3, carbs: 44.5, fat: 0.4 },
    notes: 'USDA FDC 169756 — Rice, white, long-grain, regular, enriched, cooked, 158g per cup.'
  },
  {
    id: 'gen-003',
    category: 'generic',
    input: '100g grilled chicken breast',
    expected: { calories: 165, protein: 31, carbs: 0, fat: 3.6 },
    tolerance: { carbs: 2 }, // absolute allowance for near-zero carbs
    notes: 'USDA FDC 171477 — Chicken, broiler or fryer, breast, meat only, cooked, roasted, 100g.'
  },
  {
    id: 'gen-004',
    category: 'generic',
    input: '1 medium banana',
    expected: { calories: 105, protein: 1.3, carbs: 27, fat: 0.4 },
    notes: 'USDA FDC 173944 — Banana, raw, medium (118g).'
  },
  {
    id: 'gen-005',
    category: 'generic',
    input: '1 slice white bread',
    expected: { calories: 75, protein: 2.6, carbs: 14, fat: 1 },
    notes: 'USDA FDC 172684 — Bread, white, commercially prepared, 1 slice (28g).'
  },
  {
    id: 'gen-006',
    category: 'generic',
    input: '1 tbsp olive oil',
    expected: { calories: 119, protein: 0, carbs: 0, fat: 13.5 },
    tolerance: { protein: 1, carbs: 1 },
    notes: 'USDA FDC 171413 — Oil, olive, salad or cooking, 1 tbsp (13.5g).'
  },
  {
    id: 'gen-007',
    category: 'generic',
    input: '1 cup 2% milk',
    expected: { calories: 122, protein: 8.1, carbs: 11.7, fat: 4.8 },
    notes: 'USDA FDC 173441 — Milk, reduced fat, fluid, 2% milkfat, with added vitamin A and vitamin D, 1 cup (244g).'
  },
  {
    id: 'gen-008',
    category: 'generic',
    input: '1 medium avocado',
    expected: { calories: 234, protein: 2.9, carbs: 12.5, fat: 21.4 },
    notes: 'USDA FDC 171705 — Avocados, raw, all commercial varieties, 1 avocado (150g).'
  },

  // ============================================================
  // BRANDED (6) — packaged products with published labels
  // ============================================================
  {
    id: 'brand-001',
    category: 'branded',
    input: '1 cup Cheerios',
    expected: { calories: 100, protein: 3, carbs: 20, fat: 2 },
    notes: 'General Mills Cheerios nutrition label — 1 cup (28g): 100 kcal, 3g P, 20g C, 2g F.'
  },
  {
    id: 'brand-002',
    category: 'branded',
    input: '12oz can Coca-Cola',
    expected: { calories: 140, protein: 0, carbs: 39, fat: 0 },
    tolerance: { protein: 1, fat: 1 },
    notes: 'coca-cola.com nutrition — 12 fl oz can: 140 kcal, 0g P, 39g C, 0g F.'
  },
  {
    id: 'brand-003',
    category: 'branded',
    input: '1 Kind bar dark chocolate nuts sea salt',
    expected: { calories: 200, protein: 6, carbs: 16, fat: 15 },
    notes: 'KIND Dark Chocolate Nuts & Sea Salt, 40g bar — kindsnacks.com.'
  },
  {
    id: 'brand-004',
    category: 'branded',
    input: '1 scoop Ben and Jerrys Chocolate Chip Cookie Dough',
    expected: { calories: 280, protein: 4, carbs: 33, fat: 15 },
    notes: 'Ben & Jerry\'s Chocolate Chip Cookie Dough — 2/3 cup (108g) serving per label.'
  },
  {
    id: 'brand-005',
    category: 'branded',
    input: '1 Clif Bar chocolate chip',
    expected: { calories: 250, protein: 9, carbs: 45, fat: 5 },
    notes: 'Clif Bar Chocolate Chip, 68g — clifbar.com nutrition panel.'
  },
  {
    id: 'brand-006',
    category: 'branded',
    input: '1 cup Oatly full fat oat milk',
    expected: { calories: 120, protein: 3, carbs: 16, fat: 5 },
    notes: 'Oatly Full Fat (Whole) oat milk — 240ml serving per label (oatly.com).'
  },

  // ============================================================
  // RESTAURANT (6) — chain items with published nutrition
  // ============================================================
  {
    id: 'rest-001',
    category: 'restaurant',
    input: 'Big Mac',
    expected: { calories: 550, protein: 25, carbs: 45, fat: 30 },
    notes: 'McDonald\'s Big Mac — mcdonalds.com nutrition calculator. 550 kcal, 25g P, 45g C, 30g F.'
  },
  {
    id: 'rest-002',
    category: 'restaurant',
    input: 'Starbucks Grande Caffe Latte with 2% milk',
    expected: { calories: 190, protein: 13, carbs: 19, fat: 7 },
    notes: 'Starbucks.com nutrition — Grande (16 fl oz) Caffè Latte with 2% milk.'
  },
  {
    id: 'rest-003',
    category: 'restaurant',
    input: 'Chipotle chicken burrito bowl with rice beans salsa',
    expected: { calories: 685, protein: 45, carbs: 73, fat: 20 },
    notes: 'Chipotle nutrition calculator — white rice + black beans + chicken + tomatillo-red chili salsa (no dairy). ~685 kcal.'
  },
  {
    id: 'rest-004',
    category: 'restaurant',
    input: 'Subway 6 inch turkey sandwich',
    expected: { calories: 280, protein: 18, carbs: 45, fat: 3.5 },
    notes: 'Subway 6-inch Oven Roasted Turkey on 9-Grain Wheat, no cheese, standard veg — subway.com.'
  },
  {
    id: 'rest-005',
    category: 'restaurant',
    input: 'Taco Bell Crunchwrap Supreme',
    expected: { calories: 530, protein: 16, carbs: 71, fat: 21 },
    notes: 'Taco Bell Crunchwrap Supreme — tacobell.com nutrition.'
  },
  {
    id: 'rest-006',
    category: 'restaurant',
    input: 'In-N-Out Double-Double',
    expected: { calories: 670, protein: 37, carbs: 39, fat: 41 },
    notes: 'In-N-Out Double-Double with onion — in-n-out.com/nutrition.'
  },

  // ============================================================
  // INTERNATIONAL (6) — fuzzier ground truth, cite reference
  // ============================================================
  {
    id: 'intl-001',
    category: 'international',
    input: '1 cup chicken pad thai',
    expected: { calories: 375, protein: 21, carbs: 45, fat: 14 },
    notes: 'Reference: USDA FDC 782527 (Pad Thai with chicken, 1 cup ~232g). International recipes vary.',
    tolerance: { calories: 0.25, protein: 0.25, carbs: 0.25, fat: 0.25 } // wider: recipe variation
  },
  {
    id: 'intl-002',
    category: 'international',
    input: '1 plate chicken biryani',
    expected: { calories: 580, protein: 28, carbs: 68, fat: 22 },
    notes: 'Reference: restaurant-style hyderabadi chicken biryani, ~1 plate (350g). Highly variable.',
    tolerance: { calories: 0.3, protein: 0.3, carbs: 0.3, fat: 0.3 }
  },
  {
    id: 'intl-003',
    category: 'international',
    input: '1 bowl tonkotsu ramen',
    expected: { calories: 580, protein: 24, carbs: 72, fat: 22 },
    notes: 'Reference: standard tonkotsu ramen bowl (~500g total incl. broth). Varies by chain.',
    tolerance: { calories: 0.25, protein: 0.25, carbs: 0.25, fat: 0.25 }
  },
  {
    id: 'intl-004',
    category: 'international',
    input: '1 bowl beef pho',
    expected: { calories: 420, protein: 30, carbs: 50, fat: 10 },
    notes: 'Reference: standard Vietnamese pho tai (beef), ~medium bowl 500ml broth + noodles + beef.',
    tolerance: { calories: 0.25, protein: 0.25, carbs: 0.25, fat: 0.25 }
  },
  {
    id: 'intl-005',
    category: 'international',
    input: '1 slice tiramisu',
    expected: { calories: 330, protein: 5, carbs: 30, fat: 22 },
    notes: 'Reference: standard Italian tiramisu, ~100g slice.',
    tolerance: { calories: 0.25, protein: 0.25, carbs: 0.25, fat: 0.25 }
  },
  {
    id: 'intl-006',
    category: 'international',
    input: '1 spicy tuna roll 6 pieces',
    expected: { calories: 290, protein: 11, carbs: 38, fat: 11 },
    notes: 'Reference: standard spicy tuna sushi roll, 6 pieces (~170g total).',
    tolerance: { calories: 0.25, protein: 0.25, carbs: 0.25, fat: 0.25 }
  },

  // ============================================================
  // TRICKY PORTION (5) — tests quantity/unit parsing
  // ============================================================
  {
    id: 'port-001',
    category: 'tricky-portion',
    input: 'half a cup of rice',
    expected: { calories: 103, protein: 2.15, carbs: 22.3, fat: 0.2 },
    tolerance: { fat: 1 }, // absolute for near-zero
    notes: 'USDA FDC 169756 — half of 158g cooked white rice serving = 79g.'
  },
  {
    id: 'port-002',
    category: 'tricky-portion',
    input: '3 small apples',
    expected: { calories: 234, protein: 1.2, carbs: 62, fat: 0.8 },
    tolerance: { fat: 1 },
    notes: 'USDA FDC 171688 — Apple, raw, with skin. Small = ~149g × 3.'
  },
  {
    id: 'port-003',
    category: 'tricky-portion',
    input: 'a big slice of chocolate cake',
    expected: { calories: 450, protein: 5, carbs: 60, fat: 22 },
    tolerance: { calories: 0.25, protein: 0.3, carbs: 0.25, fat: 0.25 },
    notes: 'USDA composite — chocolate layer cake with frosting, ~big slice = 125g.'
  },
  {
    id: 'port-004',
    category: 'tricky-portion',
    input: 'handful of almonds',
    expected: { calories: 164, protein: 6, carbs: 6.1, fat: 14.2 },
    notes: 'USDA FDC 170567 — Nuts, almonds, 1 oz (28g) ~= typical handful of 23 almonds.'
  },
  {
    id: 'port-005',
    category: 'tricky-portion',
    input: 'a small bowl of oatmeal',
    expected: { calories: 150, protein: 5, carbs: 27, fat: 2.5 },
    notes: 'USDA FDC 173904 — Oats, cooked with water. Small bowl ~= 1 cup cooked (234g).',
    tolerance: { calories: 0.2, protein: 0.2, carbs: 0.2, fat: 0.3 }
  },

  // ============================================================
  // MISSPELLING (4) — tests typo recovery
  // ============================================================
  {
    id: 'spell-001',
    category: 'misspelling',
    input: '2 egs and toast',
    expected: { calories: 219, protein: 15.2, carbs: 14.7, fat: 10.5 },
    notes: 'Same intent as "2 eggs and 1 slice white toast" — USDA FDC 748967 × 2 + FDC 172684 × 1.'
  },
  {
    id: 'spell-002',
    category: 'misspelling',
    input: 'chickn breast 100g',
    expected: { calories: 165, protein: 31, carbs: 0, fat: 3.6 },
    tolerance: { carbs: 2 },
    notes: 'Same as "100g chicken breast" — USDA FDC 171477.'
  },
  {
    id: 'spell-003',
    category: 'misspelling',
    input: 'vanila icecreem scoop',
    expected: { calories: 137, protein: 2.3, carbs: 15.6, fat: 7.3 },
    notes: 'Same as "1 scoop vanilla ice cream" — USDA FDC 171557, ~66g per scoop.',
    tolerance: { calories: 0.2, protein: 0.3, carbs: 0.2, fat: 0.25 }
  },
  {
    id: 'spell-004',
    category: 'misspelling',
    input: 'peanut buter 2 tbsp',
    expected: { calories: 190, protein: 7, carbs: 8, fat: 16 },
    notes: 'Same as "2 tbsp peanut butter" — USDA FDC 174292, 32g serving.'
  },

  // ============================================================
  // MULTI-ITEM (3) — tests segmentation + aggregation
  // ============================================================
  {
    id: 'multi-001',
    category: 'multi-item',
    input: '2 eggs and toast with butter',
    expected: { calories: 253, protein: 15.3, carbs: 14.7, fat: 14.3 },
    notes: '2 × FDC 748967 (eggs) + 1 × FDC 172684 (white bread slice) + 1 tsp × FDC 173430 (butter, 4.7g).'
  },
  {
    id: 'multi-002',
    category: 'multi-item',
    input: 'chicken curry with rice and naan',
    expected: { calories: 850, protein: 38, carbs: 95, fat: 32 },
    notes: 'Composite: chicken curry ~1 cup (300 kcal) + cooked rice 1 cup (205 kcal) + 1 naan (262 kcal) + sauce fat. Variable.',
    tolerance: { calories: 0.25, protein: 0.25, carbs: 0.25, fat: 0.3 }
  },
  {
    id: 'multi-003',
    category: 'multi-item',
    input: 'oatmeal with blueberries and honey',
    expected: { calories: 245, protein: 5.6, carbs: 50, fat: 2.8 },
    notes: '1 cup oatmeal cooked (150 kcal) + 1/2 cup blueberries (42 kcal) + 1 tbsp honey (64 kcal). USDA composites.',
    tolerance: { calories: 0.2, protein: 0.25, carbs: 0.2, fat: 0.3 }
  }
];
