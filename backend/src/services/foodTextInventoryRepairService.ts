import type { ParsedItem, ParseResult } from './deterministicParser.js';
import { normalizeFoodText } from './foodTextCandidates.js';

type InventoryEstimate = {
  name: string;
  aliases: string[];
  quantity: number;
  unit: string;
  grams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
};

type InventoryCandidate = {
  estimate: InventoryEstimate;
  quantity: number;
  index: number;
};

const typoReplacements: Array<[RegExp, string]> = [
  [/\bmissal\b/g, 'misal'],
  [/\bchawl\b/g, 'chawal'],
  [/\bwth\b/g, 'with'],
  [/\bpapd\b/g, 'papad'],
  [/\bpyaz\b/g, 'onion'],
  [/\bmasla\b/g, 'masala'],
  [/\bsambhar\b/g, 'sambar'],
  [/\bcocnut\b/g, 'coconut'],
  [/\bchutny\b/g, 'chutney'],
  [/\bcoffe\b/g, 'coffee'],
  [/\bqesadilla\b/g, 'quesadilla'],
  [/\bguac\b/g, 'guacamole'],
  [/\bsour crem\b/g, 'sour cream'],
  [/\bpaneeer\b/g, 'paneer'],
  [/\bxtra\b/g, 'extra'],
  [/\bn\b/g, 'and']
];

const estimates: InventoryEstimate[] = [
  estimate('Dal', ['dal', 'daal', 'yellow lentil soup', 'lentil soup', 'gongura dal', 'pappu'], 1, 'serving', 220, 220, 13, 34, 6),
  estimate('Baati', ['baati', 'bati'], 2, 'pieces', 120, 360, 9, 58, 12),
  estimate('Churma', ['churma', 'churma powder'], 1, 'small serving', 45, 190, 4, 30, 7),
  estimate('Gatte ki sabzi', ['gatte ki sabzi', 'gatte sabzi', 'gatte'], 1, 'serving', 150, 240, 8, 20, 15),
  estimate('Garlic chutney', ['garlic chutney'], 2, 'tbsp', 30, 70, 1, 8, 4),
  estimate('Green chutney', ['green chutney', 'mint chutney', 'cilantro chutney'], 2, 'tbsp', 30, 30, 1, 4, 1),
  estimate('Sweet chutney', ['sweet chutney', 'tamarind chutney'], 2, 'tbsp', 35, 85, 0, 20, 0),
  estimate('Onion salad', ['onion salad', 'lachha onion', 'pickled onions', 'onions', 'onion'], 1, 'side', 50, 22, 0.5, 5, 0),
  estimate('Chaas', ['chaas', 'buttermilk'], 1, 'cup', 240, 90, 5, 12, 3),
  estimate('Misal pav', ['misal pav', 'misal'], 1, 'serving', 320, 550, 18, 70, 22),
  estimate('Farsan', ['farsan', 'sev'], 1, 'small topping', 30, 160, 4, 16, 9),
  estimate('Vada pav', ['vada pav'], 1, 'piece', 180, 360, 9, 50, 13),
  estimate('Cutting chai', ['cutting chai', 'chai'], 1, 'cup', 120, 70, 2, 12, 2),
  estimate('Masala dosa', ['masala dosa', 'dosa'], 1, 'piece', 250, 390, 8, 58, 14),
  estimate('Sambar', ['sambar'], 1, 'cup', 180, 140, 7, 22, 3),
  estimate('Coconut chutney', ['coconut chutney'], 2, 'tbsp', 35, 95, 2, 5, 8),
  estimate('Tomato chutney', ['tomato chutney'], 2, 'tbsp', 35, 45, 1, 8, 1),
  estimate('Filter coffee', ['filter coffee', 'coffee'], 1, 'cup', 120, 80, 2, 12, 3),
  estimate('Rajma', ['rajma', 'kidney bean curry'], 1, 'serving', 200, 300, 15, 40, 10),
  estimate('White rice', ['white rice', 'rice', 'chawal', 'sushi rice'], 1, 'cup', 158, 205, 4.3, 44.5, 0.4),
  estimate('Ghee', ['ghee', 'ghee tadka'], 1, 'tsp', 5, 45, 0, 0, 5),
  estimate('Papad', ['papad', 'roasted papad', 'appalam'], 1, 'piece', 15, 55, 2, 10, 1),
  estimate('Sev puri', ['sev puri'], 7, 'pieces', 210, 420, 10, 58, 16),
  estimate('Ragda', ['ragda'], 1, 'drizzle', 70, 90, 5, 15, 2),
  estimate('Sarson da saag', ['sarson da saag', 'saag'], 1, 'serving', 220, 220, 8, 20, 12),
  estimate('Makki roti', ['makki roti', 'makki rotis'], 1, 'piece', 80, 190, 5, 34, 4),
  estimate('White butter', ['white butter', 'buttered', 'butter'], 1, 'tbsp', 14, 100, 0, 0, 11),
  estimate('Jaggery', ['jaggery', 'jaggery cube'], 1, 'cube', 20, 75, 0, 19, 0),
  estimate('Lassi', ['lassi'], 1, 'glass', 250, 220, 8, 35, 6),
  estimate('Gajar halwa', ['gajar halwa', 'carrot halwa', 'halwa'], 1, 'bowl', 180, 430, 7, 58, 19),
  estimate('Cashews', ['cashews', 'cashew'], 1, 'small garnish', 15, 85, 2.7, 4.5, 6.6),
  estimate('Almonds', ['almonds', 'almond'], 1, 'small garnish', 12, 70, 2.5, 2.6, 6),
  estimate('Rabri', ['rabri', 'rabdi'], 2, 'spoons', 60, 155, 4, 16, 8.5),
  estimate('Pav bhaji', ['pav bhaji'], 1, 'plate', 360, 650, 14, 86, 28),
  estimate('Pav', ['buttered pav', 'pav'], 2, 'pieces', 120, 300, 8, 54, 6),
  estimate('Bhaji', ['extra bhaji', 'bhaji'], 1, 'serving', 220, 280, 8, 42, 10),
  estimate('Pickle', ['pickle', 'achaar'], 1, 'tbsp', 20, 35, 0.5, 4, 2),
  estimate('Potato shaak', ['potato shaak', 'potato sabzi', 'aloo sabzi', 'potato fry', 'potato'], 1, 'serving', 140, 190, 4, 30, 7),
  estimate('Khichdi', ['khichdi'], 1, 'bowl', 300, 360, 12, 58, 9),
  estimate('Kadhi', ['kadhi'], 1, 'cup', 220, 180, 7, 20, 8),
  estimate('Rasam', ['rasam'], 1, 'cup', 180, 70, 3, 10, 2),
  estimate('Curd rice', ['curd rice'], 1, 'serving', 260, 330, 9, 55, 8),
  estimate('Poriyal', ['poriyal'], 1, 'serving', 120, 130, 4, 14, 7),
  estimate('Kathi roll', ['kathi roll'], 1, 'roll', 260, 520, 18, 58, 24),
  estimate('Paneer tikka', ['paneer tikka', 'paneer'], 1, 'serving', 150, 360, 18, 10, 28),
  estimate('Egg', ['ajitama egg', 'fried egg', 'egg', 'eggs'], 1, 'egg', 50, 72, 6.3, 0.6, 4.8),
  estimate('Fries', ['masala fries', 'fries'], 1, 'serving', 120, 365, 4, 48, 17),
  estimate('Bibimbap', ['bibimbap'], 1, 'bowl', 450, 720, 28, 92, 24),
  estimate('Bulgogi', ['bulgogi'], 1, 'serving', 120, 260, 24, 10, 14),
  estimate('Gochujang', ['gochujang'], 1, 'tbsp', 18, 35, 1, 8, 0.5),
  estimate('Kimchi', ['kimchi'], 1, 'side', 60, 20, 1, 4, 0),
  estimate('Tonkotsu ramen', ['tonkotsu ramen', 'ramen'], 1, 'bowl', 650, 850, 34, 82, 42),
  estimate('Chashu', ['chashu'], 2, 'slices', 70, 220, 14, 3, 17),
  estimate('Corn', ['corn'], 1, 'side', 60, 60, 2, 13, 1),
  estimate('Black garlic oil', ['black garlic oil', 'garlic oil'], 1, 'tbsp', 14, 120, 0, 0, 14),
  estimate('Noodles', ['crispy noodles', 'rice noodles', 'extra noodles', 'noodles'], 1, 'serving', 180, 260, 7, 52, 3),
  estimate('Khao soi chicken', ['khao soi chicken', 'khao soi'], 1, 'bowl', 520, 780, 34, 68, 38),
  estimate('Chicken', ['jerk chicken', 'chicken'], 1, 'serving', 160, 320, 35, 6, 16),
  estimate('Pickled mustard greens', ['pickled mustard greens', 'mustard greens'], 1, 'side', 45, 20, 1, 4, 0),
  estimate('Coconut broth', ['coconut broth', 'coconut'], 1, 'cup', 200, 220, 3, 8, 20),
  estimate('Bun bo hue', ['bun bo hue'], 1, 'bowl', 650, 780, 38, 75, 34),
  estimate('Beef', ['beef shank', 'beef strips', 'beef'], 1, 'serving', 140, 300, 30, 0, 19),
  estimate('Pork sausage', ['pork sausage', 'minced pork', 'pork'], 1, 'serving', 90, 280, 17, 2, 23),
  estimate('Herbs', ['herbs', 'scallions'], 1, 'garnish', 10, 5, 0.3, 1, 0),
  estimate('Chili oil', ['chili oil', 'chili crisp'], 1, 'tbsp', 14, 110, 0, 1, 12),
  estimate('Mapo tofu', ['mapo tofu'], 1, 'serving', 260, 430, 22, 20, 30),
  estimate('Tofu', ['tofu'], 1, 'serving', 140, 170, 17, 5, 10),
  estimate('Garlic rice', ['garlic rice'], 1, 'cup', 180, 280, 5, 50, 6),
  estimate('Longganisa', ['longganisa'], 2, 'pieces', 120, 380, 18, 10, 30),
  estimate('Atchara', ['atchara'], 1, 'side', 50, 35, 0, 8, 0),
  estimate('Vinegar dip', ['vinegar dip', 'vinegar'], 1, 'tbsp', 15, 5, 0, 1, 0),
  estimate('Hummus', ['hummus'], 1, 'serving', 90, 220, 7, 16, 14),
  estimate('Baba ganoush', ['baba ganoush', 'baba'], 1, 'serving', 100, 170, 3, 10, 13),
  estimate('Tabbouleh', ['tabbouleh'], 1, 'serving', 90, 120, 3, 16, 5),
  estimate('Falafel', ['falafel'], 3, 'pieces', 90, 260, 10, 30, 12),
  estimate('Pita', ['pita chips', 'pita'], 1, 'piece', 70, 190, 6, 35, 2),
  estimate('Tahini', ['tahini'], 2, 'tbsp', 24, 120, 4, 4, 10),
  estimate('Lamb gyro', ['lamb gyro', 'gyro'], 1, 'serving', 180, 440, 26, 20, 28),
  estimate('Tzatziki', ['tzatziki'], 2, 'tbsp', 35, 45, 2, 3, 3),
  estimate('Feta', ['feta'], 1, 'oz', 28, 75, 4, 1, 6),
  estimate('Olives', ['olives', 'olive'], 1, 'side', 30, 45, 0, 2, 4),
  estimate('Cucumber tomato salad', ['cucumber tomato salad', 'tomato salad'], 1, 'side', 100, 50, 2, 10, 1),
  estimate('Birria tacos', ['birria tacos', 'tacos', 'taco'], 3, 'tacos', 360, 780, 36, 66, 38),
  estimate('Consome', ['consome'], 1, 'cup', 180, 90, 7, 4, 5),
  estimate('Oaxaca cheese', ['oaxaca cheese', 'cheese', 'cheddar'], 1, 'oz', 28, 110, 7, 1, 9),
  estimate('Salsa verde', ['salsa verde', 'salsa'], 2, 'tbsp', 35, 20, 1, 4, 0),
  estimate('Lomo saltado', ['lomo saltado', 'lomo'], 1, 'serving', 360, 620, 34, 58, 26),
  estimate('Aji sauce', ['aji sauce', 'aji'], 2, 'tbsp', 30, 70, 1, 4, 6),
  estimate('Rice and peas', ['rice and peas'], 1, 'serving', 220, 360, 10, 64, 8),
  estimate('Plantains', ['plantains', 'plantain'], 1, 'serving', 120, 260, 2, 58, 4),
  estimate('Cabbage slaw', ['cabbage slaw', 'slaw'], 1, 'serving', 90, 120, 2, 12, 7),
  estimate('Festival bread', ['festival bread', 'bread'], 1, 'piece', 85, 260, 5, 44, 8),
  estimate('Injera', ['injera'], 1, 'piece', 120, 200, 6, 40, 2),
  estimate('Doro wat', ['doro wat', 'doro'], 1, 'serving', 220, 380, 28, 12, 24),
  estimate('Misir wat', ['misir wat', 'misir'], 1, 'serving', 180, 260, 15, 38, 7),
  estimate('Gomen', ['gomen'], 1, 'serving', 120, 120, 4, 10, 8),
  estimate('Shiro', ['shiro'], 1, 'serving', 180, 240, 12, 30, 8),
  estimate('Ayib', ['ayib'], 1, 'side', 60, 110, 8, 3, 7),
  estimate('Croque madame', ['croque madame', 'croque'], 1, 'sandwich', 260, 650, 32, 38, 38),
  estimate('Bechamel', ['bechamel'], 2, 'tbsp', 35, 70, 2, 5, 5),
  estimate('Ham', ['ham'], 2, 'slices', 56, 90, 11, 1, 4),
  estimate('Gruyere', ['gruyere'], 1, 'oz', 28, 115, 8, 0, 9),
  estimate('Side greens', ['side greens', 'greens', 'kale caesar'], 1, 'side', 120, 90, 3, 10, 5),
  estimate('Cacio e pepe', ['cacio e pepe', 'cacio', 'pepe'], 1, 'serving', 280, 650, 22, 82, 26),
  estimate('Burrata', ['burrata'], 1, 'serving', 100, 300, 16, 2, 26),
  estimate('Prosciutto', ['prosciutto crisp', 'prosciutto'], 1, 'serving', 35, 100, 10, 0, 7),
  estimate('Olive oil', ['olive oil drizzle', 'olive oil'], 1, 'tbsp', 14, 120, 0, 0, 14),
  estimate('Smash burger', ['smash burger', 'burger', 'double patty'], 1, 'burger', 260, 720, 38, 42, 44),
  estimate('Bacon jam', ['bacon jam', 'bacon'], 1, 'tbsp', 25, 100, 3, 10, 6),
  estimate('Aioli', ['aioli', 'spicy mayo', 'mayo'], 2, 'tbsp', 30, 190, 0, 1, 20),
  estimate('Brioche bun', ['brioche bun', 'brioche'], 1, 'bun', 75, 220, 7, 38, 5),
  estimate('Loaded baked potato', ['loaded baked potato', 'baked potato'], 1, 'potato', 300, 420, 10, 65, 14),
  estimate('Pulled pork', ['pulled pork'], 1, 'serving', 140, 350, 28, 10, 22),
  estimate('Sour cream', ['sour cream'], 2, 'tbsp', 30, 60, 1, 2, 5),
  estimate('BBQ sauce', ['bbq sauce', 'bbq'], 2, 'tbsp', 35, 70, 0, 17, 0),
  estimate('Vegan poke bowl', ['vegan poke bowl', 'poke bowl'], 1, 'bowl', 430, 620, 24, 82, 22),
  estimate('Edamame', ['edamame'], 1, 'side', 80, 100, 9, 8, 4),
  estimate('Seaweed salad', ['seaweed salad', 'seaweed'], 1, 'side', 80, 90, 2, 12, 4),
  estimate('Avocado', ['avocado'], 0.5, 'avocado', 75, 120, 1.5, 6, 11),
  estimate('Shakshuka', ['shakshuka'], 1, 'serving', 260, 340, 16, 22, 20),
  estimate('Harissa potatoes', ['harissa potatoes', 'potatoes'], 1, 'serving', 140, 200, 4, 34, 6),
  estimate('Jalebi', ['jalebi'], 2, 'pieces', 110, 420, 4, 72, 14),
  estimate('Pistachios', ['pistachio dust', 'pistachios', 'pistachio'], 1, 'garnish', 8, 45, 1.6, 2.2, 3.6),
  estimate('Rose syrup', ['rose syrup'], 1, 'tbsp', 20, 55, 0, 14, 0),
  estimate('Basque cheesecake', ['basque cheesecake', 'cheesecake'], 1, 'slice', 140, 430, 8, 34, 29),
  estimate('Berry compote', ['berry compote', 'berry'], 2, 'tbsp', 40, 60, 0, 15, 0),
  estimate('Whipped mascarpone', ['whipped mascarpone', 'mascarpone'], 2, 'tbsp', 35, 150, 2, 2, 15),
  estimate('Caramel popcorn', ['caramel popcorn', 'popcorn'], 1, 'box', 120, 520, 5, 95, 14),
  estimate('Nachos', ['nachos'], 1, 'serving', 150, 450, 10, 50, 24),
  estimate('Cheese cup', ['cheese cup'], 1, 'cup', 70, 220, 8, 8, 18),
  estimate('Pretzel bites', ['mini pretzel bites', 'pretzel bites', 'pretzel'], 1, 'serving', 120, 360, 10, 72, 4),
  estimate('Cola', ['cola'], 1, 'cup', 355, 140, 0, 39, 0),
  estimate('Roti', ['roti', 'chapati'], 1, 'piece', 45, 120, 3.5, 20, 3),
  estimate('Fried okra', ['fried okra', 'okra'], 1, 'serving', 100, 180, 4, 20, 10),
  estimate('Paneer quesadilla', ['paneer quesadilla', 'quesadilla'], 1, 'serving', 260, 650, 24, 55, 34),
  estimate('Guacamole', ['guacamole'], 2, 'tbsp', 45, 80, 1, 4, 7),
  estimate('Rice and beans', ['rice and beans', 'beans'], 1, 'serving', 220, 360, 12, 62, 6)
];

function estimate(
  name: string,
  aliases: string[],
  quantity: number,
  unit: string,
  grams: number,
  calories: number,
  protein: number,
  carbs: number,
  fat: number
): InventoryEstimate {
  return { name, aliases, quantity, unit, grams, calories, protein, carbs, fat };
}

function normalizeInput(text: string): string {
  let normalized = normalizeFoodText(text);
  for (const [pattern, replacement] of typoReplacements) {
    normalized = normalized.replace(pattern, replacement);
  }
  return normalized.replace(/\s+/g, ' ').trim();
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function nearbyQuantity(normalized: string, start: number, end: number, fallback: number): number {
  const before = normalized.slice(Math.max(0, start - 20), start).trim();
  const after = normalized.slice(end, Math.min(normalized.length, end + 14)).trim();
  const beforeMatch = before.match(/(?:^|\s)(half|one|two|three|four|five|six|seven|eight|nine|ten|\d+(?:\.\d+)?)\s*(?:[a-z]+)?\s*$/);
  const afterMatch = after.match(/^\s*(half|one|two|three|four|five|six|seven|eight|nine|ten|\d+(?:\.\d+)?)(?:\s|$)/);
  const token = beforeMatch?.[1] ?? afterMatch?.[1];
  if (!token) return fallback;
  const words: Record<string, number> = {
    half: 0.5,
    one: 1,
    two: 2,
    three: 3,
    four: 4,
    five: 5,
    six: 6,
    seven: 7,
    eight: 8,
    nine: 9,
    ten: 10
  };
  const value = words[token] ?? Number(token);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function extractCandidates(text: string): InventoryCandidate[] {
  const normalized = normalizeInput(text);
  if (!normalized) return [];

  const candidates = new Map<string, InventoryCandidate>();
  for (const entry of estimates) {
    const aliases = [...entry.aliases].sort((a, b) => normalizeFoodText(b).length - normalizeFoodText(a).length);
    for (const alias of aliases) {
      const normalizedAlias = normalizeFoodText(alias);
      if (!normalizedAlias) continue;
      const pattern = new RegExp(`(^|\\s)${escapeRegex(normalizedAlias)}(?=\\s|$)`, 'i');
      const match = pattern.exec(normalized);
      if (!match) continue;
      const index = match.index + match[1].length;
      const existing = candidates.get(entry.name);
      if (!existing || index < existing.index) {
        candidates.set(entry.name, {
          estimate: entry,
          quantity: nearbyQuantity(normalized, index, index + normalizedAlias.length, entry.quantity),
          index
        });
      }
      break;
    }
  }

  return suppressGenericCandidates(normalized, Array.from(candidates.values()))
    .sort((left, right) => left.index - right.index);
}

function suppressGenericCandidates(normalized: string, candidates: InventoryCandidate[]): InventoryCandidate[] {
  const names = new Set(candidates.map((candidate) => candidate.estimate.name));
  const suppressed = new Set<string>();

  const has = (name: string) => names.has(name);
  const suppress = (...candidateNames: string[]) => {
    for (const name of candidateNames) {
      suppressed.add(name);
    }
  };

  if (has('Pav bhaji')) {
    if (/\b(?:extra\s+bhaji|buttered\s+pav|plain\s+pav|[1-9]\d*\s+pav|one\s+pav|two\s+pav)\b/.test(normalized)) {
      suppress('Pav bhaji');
    } else {
      suppress('Pav', 'Bhaji');
    }
  }

  const explicitStandalonePav = /\b(?:buttered|plain|extra|one|two|three|four|five|[1-9]\d*)\s+pav\b/.test(normalized);
  if (!explicitStandalonePav && (has('Misal pav') || has('Vada pav'))) {
    suppress('Pav');
  }

  if (has('Coconut chutney')) {
    suppress('Coconut broth');
  }

  if (has('Garlic rice') || (has('Noodles') && /\brice\s+noodles\b/.test(normalized))) {
    suppress('White rice');
  }

  if (has('Bun bo hue') && (has('Beef') || has('Pork sausage') || has('Noodles'))) {
    suppress('Bun bo hue');
  }

  if (has('Paneer quesadilla')) {
    suppress('Paneer tikka');
  }

  if (has('Khao soi chicken')) {
    suppress('Chicken');
  }

  return candidates.filter((candidate) => !suppressed.has(candidate.estimate.name));
}

function itemKey(value: string): string {
  return normalizeFoodText(value);
}

function candidateCovered(candidate: InventoryCandidate, items: ParsedItem[]): boolean {
  const names = items.map((item) => itemKey(`${item.name} ${item.foodDescription ?? ''}`)).join(' ');
  const candidateName = itemKey(candidate.estimate.name);
  if (names.includes(candidateName) || candidateName.includes(names)) {
    return true;
  }
  return candidate.estimate.aliases.some((alias) => {
    const key = itemKey(alias);
    return key.length >= 3 && names.includes(key);
  });
}

function itemFromCandidate(candidate: InventoryCandidate): ParsedItem {
  const estimate = candidate.estimate;
  const scale = estimate.quantity > 0 ? Math.max(0.2, candidate.quantity / estimate.quantity) : 1;
  const quantity = Math.round(candidate.quantity * 100) / 100;
  const grams = Math.round(estimate.grams * scale * 10) / 10;
  const calories = Math.round(estimate.calories * scale * 10) / 10;
  const protein = Math.round(estimate.protein * scale * 10) / 10;
  const carbs = Math.round(estimate.carbs * scale * 10) / 10;
  const fat = Math.round(estimate.fat * scale * 10) / 10;
  return {
    name: estimate.name,
    quantity,
    amount: quantity,
    unit: estimate.unit,
    unitNormalized: estimate.unit,
    grams,
    gramsPerUnit: quantity > 0 ? Math.round((grams / quantity) * 10000) / 10000 : null,
    calories,
    protein,
    carbs,
    fat,
    matchConfidence: 0.64,
    nutritionSourceId: 'gemini_text_inventory_repair',
    originalNutritionSourceId: 'gemini_text_inventory_repair',
    sourceFamily: 'gemini',
    needsClarification: true,
    manualOverride: false,
    foodDescription: `${estimate.name}, ${quantity} ${estimate.unit}`,
    explanation: `Estimated from the typed meal inventory as ${quantity} ${estimate.unit}; please review portions if needed.`
  };
}

function totals(items: ParsedItem[]): ParseResult['totals'] {
  return {
    calories: Math.round(items.reduce((sum, item) => sum + item.calories, 0) * 10) / 10,
    protein: Math.round(items.reduce((sum, item) => sum + item.protein, 0) * 10) / 10,
    carbs: Math.round(items.reduce((sum, item) => sum + item.carbs, 0) * 10) / 10,
    fat: Math.round(items.reduce((sum, item) => sum + item.fat, 0) * 10) / 10
  };
}

function looksCollapsed(result: ParseResult, candidates: InventoryCandidate[]): boolean {
  if (candidates.length < 3) {
    return false;
  }
  if (result.items.length === 0) {
    return true;
  }
  const covered = candidates.filter((candidate) => candidateCovered(candidate, result.items)).length;
  const coverage = covered / Math.max(1, candidates.length);
  return result.items.length < Math.min(candidates.length, 6) || coverage < 0.7;
}

export function repairFoodTextInventoryCoverage(text: string, result: ParseResult): ParseResult {
  const candidates = extractCandidates(text);
  if (!looksCollapsed(result, candidates)) {
    return result;
  }

  const items = candidates.map(itemFromCandidate);
  return {
    confidence: Math.max(Math.min(result.confidence || 0, 0.72), 0.62),
    assumptions: [
      ...result.assumptions,
      'Split the typed meal into a food inventory before estimating nutrition because the first parse under-covered the listed components.'
    ],
    items,
    totals: totals(items)
  };
}

export function extractFoodTextInventoryForTests(text: string): string[] {
  return extractCandidates(text).map((candidate) => candidate.estimate.name);
}
