import { Router } from 'express';
import { z } from 'zod';
import { saveFoodLogStrict } from '../services/logService.js';
import { getDaySummary, getDaySummaryRange } from '../services/daySummaryService.js';
import { getDayLogs, getDayLogsRange } from '../services/dayLogsService.js';
import { getProgressSummary } from '../services/progressService.js';
import { assertLoggedAtNotInFutureForUser } from '../services/dateIntegrityService.js';
import { buildHealthSyncContract } from '../services/healthSyncContractService.js';
import { getParseRequestForUser, isParseRequestStale } from '../services/parseRequestService.js';
import { getSaveIdempotencyRecordForUser, payloadHash } from '../services/idempotencyService.js';
import { ApiError } from '../utils/errors.js';
import { config } from '../config.js';

const router = Router();

const nonNegative = z.number().finite().min(0);
const confidenceScore = z.number().finite().min(0).max(1);
const manualOverrideSchema = z.object({
  enabled: z.boolean(),
  reason: z.string().trim().max(500).optional(),
  editedFields: z.array(z.string().trim().min(1).max(50)).max(30).default([])
});

const itemSchema = z.object({
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

const saveLogSchema = z.object({
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

const summaryQuerySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be in YYYY-MM-DD format'),
  tz: z.string().trim().min(1).max(100).optional()
});

const progressQuerySchema = z.object({
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'from must be in YYYY-MM-DD format'),
  to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'to must be in YYYY-MM-DD format'),
  tz: z.string().trim().min(1).max(100).optional()
});

function normalizeRawText(value: string): string {
  return value.trim().replace(/\s+/g, ' ');
}

function hasManualOverride(item: z.infer<typeof itemSchema>): boolean {
  if (typeof item.manualOverride === 'boolean') {
    return item.manualOverride;
  }
  if (item.manualOverride && typeof item.manualOverride === 'object') {
    return item.manualOverride.enabled;
  }
  return false;
}

function normalizeManualOverride(item: z.infer<typeof itemSchema>): { enabled: boolean; reason?: string; editedFields: string[] } | null {
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

function roundOneDecimal(value: number): number {
  return Math.round(value * 10) / 10;
}

function totalsFromItems(items: Array<z.infer<typeof itemSchema>>): { calories: number; protein: number; carbs: number; fat: number } {
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

router.post('/', async (req, res, next) => {
  try {
    const body = saveLogSchema.parse(req.body);
    const auth = res.locals.auth as { userId: string; authProvider?: string; email?: string | null };
    const userId = auth.userId;
    const idempotencyKey = req.header('idempotency-key');
    if (!idempotencyKey || !idempotencyKey.trim()) {
      throw new ApiError(400, 'MISSING_IDEMPOTENCY_KEY', 'Idempotency-Key header is required');
    }

    // Contract precedence: idempotency conflict/replay takes priority over deep payload validation.
    const normalizedKey = idempotencyKey.trim();
    const requestedPayloadHash = payloadHash(body);
    const existing = await getSaveIdempotencyRecordForUser(userId, normalizedKey);
    if (existing) {
      if (existing.payloadHash !== requestedPayloadHash) {
        throw new ApiError(409, 'IDEMPOTENCY_CONFLICT', 'Idempotency key reused with different payload');
      }
      const payload = existing.responseJson as { logId?: string; status?: string; healthSync?: { healthWriteKey?: string } };
      const resolvedLogId = (payload?.logId && payload.logId.trim()) || existing.logId;
      const resolvedStatus = payload?.status === 'saved' ? 'saved' : 'saved';
      const resolvedHealthSync =
        payload?.healthSync?.healthWriteKey && payload.healthSync.healthWriteKey.trim().length > 0
          ? payload.healthSync
          : buildHealthSyncContract(userId, resolvedLogId);

      res.status(200).json({
        logId: resolvedLogId,
        status: resolvedStatus,
        healthSync: resolvedHealthSync
      });
      return;
    }

    if (body.parseVersion !== config.parseVersion) {
      throw new ApiError(422, 'INVALID_PARSE_REFERENCE', 'parseVersion does not match current parser version');
    }

    const parseRequest = await getParseRequestForUser(userId, body.parseRequestId);
    if (!parseRequest) {
      throw new ApiError(422, 'INVALID_PARSE_REFERENCE', 'Unknown parseRequestId');
    }

    if (isParseRequestStale(parseRequest)) {
      throw new ApiError(422, 'INVALID_PARSE_REFERENCE', 'Stale parseRequestId');
    }

    if (parseRequest.parseVersion !== body.parseVersion) {
      throw new ApiError(422, 'INVALID_PARSE_REFERENCE', 'parseRequestId parseVersion mismatch');
    }

    if (normalizeRawText(parseRequest.rawText) !== normalizeRawText(body.parsedLog.rawText)) {
      throw new ApiError(422, 'INVALID_PARSE_REFERENCE', 'parsedLog rawText does not match parseRequest');
    }

    const loggedAt = new Date(body.parsedLog.loggedAt);
    await assertLoggedAtNotInFutureForUser(userId, loggedAt);

    const unresolvedItems = body.parsedLog.items.filter((item) => item.needsClarification === true && !hasManualOverride(item));
    if (unresolvedItems.length > 0) {
      throw new ApiError(422, 'NEEDS_CLARIFICATION', 'One or more items require clarification before save.');
    }

    const invalidManualOverrides = body.parsedLog.items.filter((item) => {
      const manual = normalizeManualOverride(item);
      if (!manual?.enabled) {
        return false;
      }
      return !((item.originalNutritionSourceId || item.nutritionSourceId || '').trim());
    });
    if (invalidManualOverrides.length > 0) {
      throw new ApiError(422, 'INVALID_MANUAL_OVERRIDE', 'Manual override items must include original source provenance.');
    }

    const computedTotals = totalsFromItems(body.parsedLog.items);
    const providedTotals = body.parsedLog.totals;
    if (
      roundOneDecimal(providedTotals.calories) !== computedTotals.calories ||
      roundOneDecimal(providedTotals.protein) !== computedTotals.protein ||
      roundOneDecimal(providedTotals.carbs) !== computedTotals.carbs ||
      roundOneDecimal(providedTotals.fat) !== computedTotals.fat
    ) {
      throw new ApiError(422, 'TOTALS_MISMATCH', 'parsedLog totals must equal the sum of item nutrition values.');
    }

    const saved = await saveFoodLogStrict({
      userId,
      authProvider: auth.authProvider,
      userEmail: auth.email,
      idempotencyKey: normalizedKey,
      payload: body,
      log: {
        userId,
        authProvider: auth.authProvider,
        userEmail: auth.email,
        rawText: body.parsedLog.rawText,
        loggedAt: body.parsedLog.loggedAt,
        mealType: body.parsedLog.mealType,
        confidence: body.parsedLog.confidence,
        imageRef: body.parsedLog.imageRef,
        inputKind: body.parsedLog.inputKind,
        totals: body.parsedLog.totals,
        sourcesUsed: body.parsedLog.sourcesUsed,
        assumptions: body.parsedLog.assumptions,
        items: body.parsedLog.items.map((item) => ({
          foodName: item.name,
          quantity: item.amount ?? item.quantity,
          amount: item.amount ?? item.quantity,
          unit: item.unitNormalized ?? item.unit,
          unitNormalized: item.unitNormalized ?? item.unit,
          grams: item.grams,
          gramsPerUnit: item.gramsPerUnit ?? ((item.amount ?? item.quantity) > 0 ? item.grams / (item.amount ?? item.quantity) : null),
          calories: item.calories,
          protein: item.protein,
          carbs: item.carbs,
          fat: item.fat,
          nutritionSourceId: item.nutritionSourceId,
          originalNutritionSourceId: item.originalNutritionSourceId || item.nutritionSourceId,
          sourceFamily: item.sourceFamily ?? (hasManualOverride(item) ? 'manual' : undefined),
          needsClarification: item.needsClarification ?? false,
          manualOverrideMeta: normalizeManualOverride(item),
          matchConfidence: item.matchConfidence
        }))
      }
    });

    res.status(200).json(saved);
  } catch (err) {
    next(err);
  }
});

router.get('/day-summary', async (req, res, next) => {
  try {
    const query = summaryQuerySchema.parse(req.query);
    const userId = res.locals.auth.userId as string;
    const summary = await getDaySummary(userId, query.date, query.tz);
    res.status(200).json(summary);
  } catch (err) {
    next(err);
  }
});

router.get('/day-logs', async (req, res, next) => {
  try {
    const query = summaryQuerySchema.parse(req.query);
    const userId = res.locals.auth.userId as string;
    const logs = await getDayLogs(userId, query.date, query.tz);
    res.status(200).json(logs);
  } catch (err) {
    next(err);
  }
});

const dayRangeQuerySchema = z.object({
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'from must be in YYYY-MM-DD format'),
  to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'to must be in YYYY-MM-DD format'),
  tz: z.string().trim().min(1).max(100).optional()
});

router.get('/day-range', async (req, res, next) => {
  try {
    const query = dayRangeQuerySchema.parse(req.query);
    const userId = res.locals.auth.userId as string;
    const [summaries, logs] = await Promise.all([
      getDaySummaryRange(userId, query.from, query.to, query.tz),
      getDayLogsRange(userId, query.from, query.to, query.tz)
    ]);
    res.status(200).json({ summaries, logs });
  } catch (err) {
    next(err);
  }
});

router.get('/progress', async (req, res, next) => {
  try {
    if (!config.progressFeatureEnabled) {
      throw new ApiError(404, 'FEATURE_DISABLED', 'Progress feature is disabled');
    }
    const query = progressQuerySchema.parse(req.query);
    const userId = res.locals.auth.userId as string;
    const progress = await getProgressSummary(userId, query.from, query.to, query.tz);
    res.status(200).json(progress);
  } catch (err) {
    next(err);
  }
});

export default router;
