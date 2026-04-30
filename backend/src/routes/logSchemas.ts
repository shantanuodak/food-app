import { z } from 'zod';

const nonNegative = z.number().finite().min(0);
const confidenceScore = z.number().finite().min(0).max(1);

const manualOverrideSchema = z.object({
  enabled: z.boolean(),
  reason: z.string().trim().max(500).optional(),
  editedFields: z.array(z.string().trim().min(1).max(50)).max(30).default([])
});

export const itemSchema = z.object({
  name: z.string().trim().min(1).max(100),
  quantity: nonNegative,
  amount: nonNegative.optional(),
  unit: z.string().trim().min(1).max(30),
  unitNormalized: z.string().trim().min(1).max(30).optional(),
  grams: nonNegative,
  gramsPerUnit: nonNegative.nullable().optional(),
  calories: nonNegative,
  protein: nonNegative,
  carbs: nonNegative,
  fat: nonNegative,
  nutritionSourceId: z.string().trim().min(1).max(120),
  originalNutritionSourceId: z.string().trim().min(1).max(120).optional(),
  sourceFamily: z.enum(['cache', 'gemini', 'manual']).optional(),
  matchConfidence: confidenceScore,
  needsClarification: z.boolean().optional(),
  manualOverride: z.union([z.boolean(), manualOverrideSchema]).optional()
});

export const saveLogSchema = z.object({
  parseRequestId: z.string().trim().min(1).max(120),
  parseVersion: z.string().trim().min(1).max(20),
  parsedLog: z.object({
    rawText: z.string().trim().min(1).max(500),
    loggedAt: z.string().datetime(),
    mealType: z.string().trim().min(1).max(40).optional(),
    confidence: confidenceScore,
    imageRef: z.string().trim().min(1).max(500).optional(),
    inputKind: z.enum(['text', 'image', 'voice', 'manual']).optional(),
    totals: z.object({
      calories: nonNegative,
      protein: nonNegative,
      carbs: nonNegative,
      fat: nonNegative
    }),
    sourcesUsed: z.array(z.enum(['cache', 'gemini', 'manual'])).max(10).optional(),
    assumptions: z.array(z.string().max(500)).max(20).optional().default([]),
    items: z.array(itemSchema).max(100)
  })
});

export const patchLogSchema = z.object({
  parseRequestId: z.string().trim().min(1).max(120).optional(),
  parseVersion: z.string().trim().min(1).max(20).optional(),
  parsedLog: z.object({
    rawText: z.string().trim().min(1).max(500),
    loggedAt: z.string().datetime().optional(),
    mealType: z.string().trim().min(1).max(40).optional(),
    confidence: confidenceScore,
    imageRef: z.string().trim().min(1).max(500).nullable().optional(),
    inputKind: z.enum(['text', 'image', 'voice', 'manual']).optional(),
    totals: z.object({
      calories: nonNegative,
      protein: nonNegative,
      carbs: nonNegative,
      fat: nonNegative
    }),
    sourcesUsed: z.array(z.enum(['cache', 'gemini', 'manual'])).max(10).optional(),
    assumptions: z.array(z.string().max(500)).max(20).optional().default([]),
    items: z.array(itemSchema).max(100)
  })
});

const dateQuery = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be in YYYY-MM-DD format');

export const summaryQuerySchema = z.object({
  date: dateQuery,
  tz: z.string().trim().min(1).max(100).optional()
});

export const progressQuerySchema = z.object({
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'from must be in YYYY-MM-DD format'),
  to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'to must be in YYYY-MM-DD format'),
  tz: z.string().trim().min(1).max(100).optional()
});

export const streakQuerySchema = z.object({
  range: z.coerce.number().int().refine((value) => value === 30 || value === 365, {
    message: 'range must be 30 or 365'
  }).default(30),
  to: dateQuery.optional(),
  tz: z.string().trim().min(1).max(100).optional()
});

export const dayRangeQuerySchema = z.object({
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'from must be in YYYY-MM-DD format'),
  to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'to must be in YYYY-MM-DD format'),
  tz: z.string().trim().min(1).max(100).optional()
});

export const logIdParamSchema = z.object({
  id: z.string().uuid('id must be a UUID')
});

export type LogItemSchema = z.infer<typeof itemSchema>;

export function normalizeRawText(value: string): string {
  return value.trim().replace(/\s+/g, ' ');
}

export function hasManualOverride(item: LogItemSchema): boolean {
  if (typeof item.manualOverride === 'boolean') {
    return item.manualOverride;
  }
  if (item.manualOverride && typeof item.manualOverride === 'object') {
    return item.manualOverride.enabled;
  }
  return false;
}

export function normalizeManualOverride(item: LogItemSchema): { enabled: boolean; reason?: string; editedFields: string[] } | null {
  if (typeof item.manualOverride === 'boolean') {
    if (!item.manualOverride) return null;
    return {
      enabled: true,
      reason: 'Adjusted manually in app.',
      editedFields: []
    };
  }
  if (!item.manualOverride || !item.manualOverride.enabled) {
    return null;
  }
  return {
    enabled: true,
    reason: item.manualOverride.reason,
    editedFields: item.manualOverride.editedFields || []
  };
}

export function roundOneDecimal(value: number): number {
  return Math.round(value * 10) / 10;
}

export function totalsFromItems(items: LogItemSchema[]): { calories: number; protein: number; carbs: number; fat: number } {
  const totals = items.reduce(
    (acc, item) => {
      acc.calories += item.calories;
      acc.protein += item.protein;
      acc.carbs += item.carbs;
      acc.fat += item.fat;
      return acc;
    },
    { calories: 0, protein: 0, carbs: 0, fat: 0 }
  );

  return {
    calories: roundOneDecimal(totals.calories),
    protein: roundOneDecimal(totals.protein),
    carbs: roundOneDecimal(totals.carbs),
    fat: roundOneDecimal(totals.fat)
  };
}
