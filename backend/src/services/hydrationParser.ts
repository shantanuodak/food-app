export type HydrationParseStatus = 'matched' | 'needs_amount' | 'not_hydration';

export type HydrationUnit = 'ml' | 'l' | 'fl_oz' | 'cup';

export type HydrationParseResult = {
  status: HydrationParseStatus;
  rawText: string;
  normalizedText: string;
  amountMl: number | null;
  inputAmount: number | null;
  inputUnit: HydrationUnit | null;
  confidence: number;
  reasonCodes: string[];
  suggestions: HydrationSuggestion[];
};

export type HydrationSuggestion = {
  amountMl: number;
  label: string;
};

const ML_PER_LITER = 1000;
const ML_PER_FLUID_OUNCE = 29.5735295625;
const ML_PER_CUP = 236.5882365;

const SUGGESTIONS_METRIC: HydrationSuggestion[] = [
  { amountMl: 250, label: '250 ml' },
  { amountMl: 500, label: '500 ml' },
  { amountMl: 750, label: '750 ml' }
];

const NUMBER_WORDS = new Map<string, number>([
  ['a', 1],
  ['an', 1],
  ['one', 1],
  ['two', 2],
  ['three', 3],
  ['four', 4],
  ['five', 5],
  ['six', 6],
  ['seven', 7],
  ['eight', 8],
  ['nine', 9],
  ['ten', 10],
  ['eleven', 11],
  ['twelve', 12],
  ['half', 0.5]
]);

const UNIT_PATTERN =
  '(?:fl\\.?\\s*oz\\.?|fluid\\s+ounces?|fluid\\s+ounce|ounces?|ounce|oz\\.?|milliliters?|millilitres?|ml|m\\s*l|liters?|litres?|l|cups?|cup)';

const QUANTITY_PATTERN =
  '(?:\\d+\\s+\\d+\\/\\d+|\\d+\\/\\d+|\\d+(?:\\.\\d+)?|\\.\\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|half)(?:\\s+and\\s+(?:a\\s+)?half)?';

const EXPLICIT_VOLUME_RE = new RegExp(`\\b(${QUANTITY_PATTERN})\\s*(${UNIT_PATTERN})\\b`, 'i');

const HYDRATION_RE = /\b(?:water|waters|h2o|aqua|sparkling\s+water|mineral\s+water|seltzer|club\s+soda)\b/i;

const EXCLUDED_RE =
  /\b(?:watermelon|coconut\s+water|tonic\s+water|vitamin\s+water|protein\s+water|coffee|tea|juice|milk|smoothie|shake|cola|beer|wine|cocktail|sports\s+drink|energy\s+drink)\b/i;

export function parseHydrationText(text: string): HydrationParseResult {
  const rawText = text;
  const normalizedText = normalizeText(text);

  if (!normalizedText || !HYDRATION_RE.test(normalizedText) || EXCLUDED_RE.test(normalizedText)) {
    return result('not_hydration', rawText, normalizedText, null, null, null, 0, ['not_water'], []);
  }

  const volume = extractVolume(normalizedText);
  if (!volume) {
    return result('needs_amount', rawText, normalizedText, null, null, null, 0.68, ['missing_amount'], SUGGESTIONS_METRIC);
  }

  const amountMl = toMilliliters(volume.amount, volume.unit);
  if (!Number.isFinite(amountMl) || amountMl <= 0) {
    return result('needs_amount', rawText, normalizedText, null, null, null, 0.5, ['invalid_amount'], SUGGESTIONS_METRIC);
  }

  if (amountMl > 10000) {
    return result('needs_amount', rawText, normalizedText, null, volume.amount, volume.unit, 0.5, ['amount_too_large'], SUGGESTIONS_METRIC);
  }

  return result('matched', rawText, normalizedText, roundMl(amountMl), volume.amount, volume.unit, 0.98, [], []);
}

export function hydrationAmountToMl(amount: number, unit: HydrationUnit): number {
  return roundMl(toMilliliters(amount, unit));
}

function result(
  status: HydrationParseStatus,
  rawText: string,
  normalizedText: string,
  amountMl: number | null,
  inputAmount: number | null,
  inputUnit: HydrationUnit | null,
  confidence: number,
  reasonCodes: string[],
  suggestions: HydrationSuggestion[]
): HydrationParseResult {
  return {
    status,
    rawText,
    normalizedText,
    amountMl,
    inputAmount,
    inputUnit,
    confidence,
    reasonCodes,
    suggestions
  };
}

function normalizeText(value: string): string {
  return value
    .toLowerCase()
    .replace(/[’']/g, '')
    .replace(/[,;:()]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractVolume(text: string): { amount: number; unit: HydrationUnit } | null {
  const match = text.match(EXPLICIT_VOLUME_RE);
  if (!match) {
    return null;
  }

  const amount = parseAmount(match[1] || '');
  const unit = normalizeUnit(match[2] || '');
  if (amount === null || unit === null) {
    return null;
  }
  return { amount, unit };
}

function parseAmount(value: string): number | null {
  const normalized = value.trim().toLowerCase().replace(/\s+/g, ' ');
  const halfSuffix = normalized.match(/^(.+?)\s+and\s+(?:a\s+)?half$/);
  if (halfSuffix?.[1]) {
    const whole = parseAmount(halfSuffix[1]);
    return whole === null ? null : whole + 0.5;
  }

  const mixedFraction = normalized.match(/^(\d+)\s+(\d+)\/(\d+)$/);
  if (mixedFraction) {
    const whole = Number(mixedFraction[1]);
    const numerator = Number(mixedFraction[2]);
    const denominator = Number(mixedFraction[3]);
    if (denominator === 0) return null;
    return whole + numerator / denominator;
  }

  const fraction = normalized.match(/^(\d+)\/(\d+)$/);
  if (fraction) {
    const numerator = Number(fraction[1]);
    const denominator = Number(fraction[2]);
    if (denominator === 0) return null;
    return numerator / denominator;
  }

  const numeric = Number(normalized);
  if (Number.isFinite(numeric)) {
    return numeric;
  }

  return NUMBER_WORDS.get(normalized) ?? null;
}

function normalizeUnit(value: string): HydrationUnit | null {
  const normalized = value.toLowerCase().replace(/\./g, '').replace(/\s+/g, ' ').trim();
  if (normalized === 'ml' || normalized === 'm l' || normalized.startsWith('milliliter') || normalized.startsWith('millilitre')) {
    return 'ml';
  }
  if (normalized === 'l' || normalized.startsWith('liter') || normalized.startsWith('litre')) {
    return 'l';
  }
  if (normalized === 'oz' || normalized === 'ounce' || normalized === 'ounces' || normalized.startsWith('fluid ounce') || normalized === 'fl oz') {
    return 'fl_oz';
  }
  if (normalized === 'cup' || normalized === 'cups') {
    return 'cup';
  }
  return null;
}

function toMilliliters(amount: number, unit: HydrationUnit): number {
  switch (unit) {
    case 'ml':
      return amount;
    case 'l':
      return amount * ML_PER_LITER;
    case 'fl_oz':
      return amount * ML_PER_FLUID_OUNCE;
    case 'cup':
      return amount * ML_PER_CUP;
  }
}

function roundMl(value: number): number {
  return Math.round(value);
}
