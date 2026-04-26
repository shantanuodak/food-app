/**
 * Deterministic conflict detection between a user's stated diet
 * preferences / allergies and the names of the items the parser returned.
 *
 * Runs purely in memory after the LLM round-trip — no extra LLM calls,
 * no DB hit beyond the single `getDietAndAllergies` lookup that already
 * happens in `parseOrchestrator`.
 *
 * IMPORTANT: the allergy token table here is mirrored on iOS in
 * `Food App/OnboardingFlowModels.swift` (`AllergyChoice.matchTokens`).
 * Backend is the authoritative source. If you edit one, edit the other.
 */

export type DietaryFlagRule = 'allergy' | 'diet';
export type DietaryFlagSeverity = 'warning' | 'critical';

export type DietaryFlag = {
  itemName: string;
  rule: DietaryFlagRule;
  /** The specific rule triggered, e.g. 'peanuts', 'vegetarian'. */
  ruleKey: string;
  /** The substring inside `itemName` that triggered the match (lowercased). */
  matchedToken: string;
  severity: DietaryFlagSeverity;
};

/** Allergy → lowercase substrings to look for inside parsed item names. */
const ALLERGY_TOKENS: Record<string, string[]> = {
  peanuts: ['peanut'],
  tree_nuts: ['almond', 'walnut', 'cashew', 'pecan', 'pistachio', 'hazelnut', 'macadamia', 'brazil nut'],
  gluten: ['bread', 'pasta', 'wheat', 'flour', 'noodle', 'barley', 'rye', 'couscous', 'cracker', 'pita', 'tortilla', 'bagel', 'pretzel'],
  dairy: ['milk', 'cheese', 'butter', 'cream', 'yogurt', 'yoghurt', 'ice cream', 'whey', 'paneer', 'ghee'],
  eggs: ['egg', 'omelet', 'omelette', 'frittata', 'quiche'],
  shellfish: ['shrimp', 'prawn', 'lobster', 'crab', 'crawfish', 'scallop', 'clam', 'oyster', 'mussel'],
  fish: ['salmon', 'tuna', 'cod', 'tilapia', 'mackerel', 'trout', 'halibut', 'sardine', 'anchovy', 'bass'],
  soy: ['soy', 'tofu', 'edamame', 'tempeh', 'miso', 'soybean'],
  sesame: ['sesame', 'tahini']
};

/** Diet preference → lowercase substrings that conflict. Only preferences
 *  with name-deterministic rules are listed; aspirational ones (high protein,
 *  low sodium, mediterranean, low carb, keto) are skipped because they need
 *  macro/nutrient analysis, not name matching. */
const DIET_TOKENS: Record<string, string[]> = {
  vegetarian: [
    'meat', 'chicken', 'beef', 'pork', 'ham', 'bacon', 'turkey', 'lamb', 'sausage', 'veal', 'duck', 'goose',
    // strict vegetarian also excludes seafood
    'salmon', 'tuna', 'cod', 'tilapia', 'shrimp', 'prawn', 'lobster', 'crab', 'fish'
  ],
  vegan: [
    // everything vegetarian rules out
    'meat', 'chicken', 'beef', 'pork', 'ham', 'bacon', 'turkey', 'lamb', 'sausage', 'veal', 'duck', 'goose',
    'salmon', 'tuna', 'cod', 'tilapia', 'shrimp', 'prawn', 'lobster', 'crab', 'fish',
    // plus animal products
    'milk', 'cheese', 'butter', 'cream', 'yogurt', 'yoghurt', 'whey', 'paneer', 'ghee',
    'egg', 'omelet', 'omelette', 'honey'
  ],
  pescatarian: ['meat', 'chicken', 'beef', 'pork', 'ham', 'bacon', 'turkey', 'lamb', 'sausage', 'veal', 'duck', 'goose'],
  gluten_free: ['bread', 'pasta', 'wheat', 'flour', 'noodle', 'barley', 'rye', 'couscous', 'cracker', 'pita', 'tortilla', 'bagel', 'pretzel'],
  dairy_free: ['milk', 'cheese', 'butter', 'cream', 'yogurt', 'yoghurt', 'whey', 'paneer', 'ghee'],
  halal: ['pork', 'ham', 'bacon', 'wine', 'beer', 'sake', 'liquor']
};

export type ConflictInput = {
  itemNames: string[];
  /** Comma-separated diet preference keys, e.g. "vegetarian,low_carb". The iOS
   *  client serializes the user's selected `PreferenceChoice` values this way. */
  dietPreference: string | null;
  /** Allergy keys, e.g. ["peanuts", "shellfish"]. */
  allergies: string[];
};

/**
 * Returns one `DietaryFlag` per (item, triggering rule). An item that hits
 * multiple rules (e.g. "ham sandwich" with vegetarian + halal) yields multiple
 * flags so the iOS UI can show specific reasons rather than a single vague one.
 */
export function detectDietaryConflicts(input: ConflictInput): DietaryFlag[] {
  if (input.itemNames.length === 0) {
    return [];
  }

  const dietKeys = (input.dietPreference || '')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter((s) => s.length > 0 && s !== 'no_preference');

  const allergyKeys = input.allergies.map((s) => s.trim().toLowerCase()).filter((s) => s.length > 0);

  const flags: DietaryFlag[] = [];

  for (const rawName of input.itemNames) {
    const name = rawName.toLowerCase();

    // Allergies — critical
    for (const allergyKey of allergyKeys) {
      const tokens = ALLERGY_TOKENS[allergyKey];
      if (!tokens) continue;
      const hit = tokens.find((token) => name.includes(token));
      if (hit) {
        flags.push({
          itemName: rawName,
          rule: 'allergy',
          ruleKey: allergyKey,
          matchedToken: hit,
          severity: 'critical'
        });
      }
    }

    // Diet preferences — warning
    for (const dietKey of dietKeys) {
      const tokens = DIET_TOKENS[dietKey];
      if (!tokens) continue;
      const hit = tokens.find((token) => name.includes(token));
      if (hit) {
        flags.push({
          itemName: rawName,
          rule: 'diet',
          ruleKey: dietKey,
          matchedToken: hit,
          severity: 'warning'
        });
      }
    }
  }

  return flags;
}
