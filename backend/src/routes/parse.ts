import { Router } from 'express';
import { z } from 'zod';
import { runEscalationParse } from '../services/aiEscalationService.js';
import { getBudgetSnapshotForUser, recordAiCostWithBudgetGuard } from '../services/aiCostService.js';
import { assertLoggedAtNotInFutureForUser } from '../services/dateIntegrityService.js';
import { createParseRequest, getParseRequestForUser, isParseRequestStale } from '../services/parseRequestService.js';
import { ApiError } from '../utils/errors.js';
import { config } from '../config.js';
import { executePrimaryParse, executePrimaryParseStreaming } from '../services/parseOrchestrator.js';
import { getGeminiCircuitRetryAfterSeconds } from '../services/geminiFlashClient.js';
import { collectSourcesUsed } from '../services/parseContractService.js';
import { parseImageWithGemini } from '../services/imageParseService.js';
import { checkParseRateLimit } from '../services/parseRateLimiterService.js';
import { getDietAndAllergies } from '../services/onboardingService.js';
import { detectDietaryConflicts } from '../services/dietaryConflictService.js';

const router = Router();
const supportedImageMimeTypes = new Set(['image/jpeg', 'image/png', 'image/heic']);

const parseSchema = z.object({
  text: z
    .string()
    .transform((value) => value.trim())
    .refine((value) => value.length > 0, 'text must not be empty')
    .refine((value) => value.length <= 500, 'text exceeds max length (500)'),
  loggedAt: z.string().datetime()
});

const escalateSchema = z.object({
  parseRequestId: z.string().trim().min(1).max(120),
  loggedAt: z.string().datetime()
});

const imageParseSchema = z.object({
  imageBase64: z.string().trim().min(1),
  mimeType: z.string().trim().min(1).max(100),
  loggedAt: z
    .string()
    .datetime()
    .optional()
});

function roundUsd(value: number): number {
  return Math.round(value * 1000) / 1000;
}

router.post('/image', async (req, res, next) => {
  const startedAt = process.hrtime.bigint();
  try {
    if (!config.aiImageParseEnabled) {
      throw new ApiError(403, 'IMAGE_PARSE_DISABLED', 'Image parse is disabled');
    }

    const auth = res.locals.auth as { userId: string; authProvider?: string; email?: string | null };
    const rateLimit = checkParseRateLimit(auth.userId);
    if (!rateLimit.allowed) {
      const error = new ApiError(429, 'RATE_LIMITED', 'Too many parse requests. Please retry shortly.');
      (error as ApiError & { retryAfterSeconds?: number }).retryAfterSeconds = rateLimit.retryAfterSeconds;
      throw error;
    }

    const body = imageParseSchema.parse(req.body || {});
    if (!supportedImageMimeTypes.has(body.mimeType)) {
      throw new ApiError(400, 'INVALID_INPUT', 'Unsupported image type. Use JPEG, PNG, or HEIC.');
    }
    const imageBytes = Math.floor(Buffer.byteLength(body.imageBase64, 'base64'));
    if (!Number.isFinite(imageBytes) || imageBytes <= 0) {
      throw new ApiError(400, 'INVALID_INPUT', 'Image file is empty.');
    }
    if (imageBytes > Math.max(1_024, config.aiImageMaxBytes)) {
      throw new ApiError(400, 'INVALID_INPUT', `Image exceeds max size (${config.aiImageMaxBytes} bytes).`);
    }

    const loggedAt = body.loggedAt ? new Date(body.loggedAt) : new Date();
    if (Number.isNaN(loggedAt.valueOf())) {
      throw new ApiError(400, 'INVALID_INPUT', 'Invalid loggedAt timestamp');
    }
    await assertLoggedAtNotInFutureForUser(auth.userId, loggedAt);

    const parseRequestId = res.locals.requestId as string;
    const parsedImage = await parseImageWithGemini({
      mimeType: body.mimeType,
      dataBase64: body.imageBase64
    });

    let budget = await getBudgetSnapshotForUser({
      userId: auth.userId,
      dailyBudgetUsd: config.aiDailyBudgetUsd,
      userSoftCapUsd: config.aiUserSoftCapUsd
    });

    for (const usageEvent of parsedImage.usageEvents) {
      budget = await recordAiCostWithBudgetGuard({
        userId: auth.userId,
        requestId: parseRequestId,
        feature: usageEvent.feature,
        model: usageEvent.usage.model,
        inputTokens: usageEvent.usage.inputTokens,
        outputTokens: usageEvent.usage.outputTokens,
        estimatedCostUsd: usageEvent.estimatedCostUsd,
        dailyBudgetUsd: config.aiDailyBudgetUsd,
        userSoftCapUsd: config.aiUserSoftCapUsd
      });
    }

    const needsClarification = parsedImage.result.confidence < config.aiImageConfidenceMin;
    await createParseRequest({
      requestId: parseRequestId,
      userId: auth.userId,
      rawText: parsedImage.extractedText,
      needsClarification,
      cacheHit: false,
      primaryRoute: 'gemini',
      authProvider: auth.authProvider,
      email: auth.email
    });

    const parseDurationMs = Number(process.hrtime.bigint() - startedAt) / 1_000_000;
    const roundedDurationMs = Math.round(parseDurationMs * 10) / 10;
    const sourcesUsed = collectSourcesUsed(parsedImage.result.items, 'gemini', false);

    // Image parse bypasses the orchestrator, so run the diet/allergy check inline.
    // Soft-fail: never block a parse on dietary lookup.
    let imageDietaryFlags: ReturnType<typeof detectDietaryConflicts> = [];
    try {
      const dietaryProfile = await getDietAndAllergies(auth.userId);
      if (dietaryProfile.dietPreference || dietaryProfile.allergies.length > 0) {
        imageDietaryFlags = detectDietaryConflicts({
          itemNames: parsedImage.result.items.map((item) => item.name),
          dietPreference: dietaryProfile.dietPreference,
          allergies: dietaryProfile.allergies
        });
      }
    } catch (err) {
      console.warn('[dietary] image flag computation failed; returning no flags', err);
    }

    res.setHeader('x-parse-route', 'gemini');
    res.setHeader('x-parse-duration-ms', String(roundedDurationMs));
    res.setHeader('x-parse-cache', 'miss');
    res.setHeader('x-parse-fallback', parsedImage.fallbackUsed ? 'used' : 'not_used');
    res.setHeader('x-parse-clarification', needsClarification ? 'needed' : 'not_needed');
    res.setHeader('x-parse-input-kind', 'image');
    res.setHeader('x-vision-model', parsedImage.model);
    res.setHeader('x-vision-fallback', parsedImage.fallbackUsed ? 'used' : 'not_used');

    res.status(200).json({
      requestId: parseRequestId,
      parseRequestId,
      parseVersion: config.parseVersion,
      route: 'gemini',
      cacheHit: false,
      sourcesUsed,
      fallbackUsed: parsedImage.fallbackUsed,
      fallbackModel: parsedImage.fallbackUsed ? parsedImage.model : null,
      budget: {
        dailyLimitUsd: budget.dailyBudgetUsd,
        dailyUsedTodayUsd: roundUsd(budget.globalUsedTodayUsd),
        userSoftCapUsd: budget.userSoftCapUsd,
        userUsedTodayUsd: roundUsd(budget.userUsedTodayUsd),
        userSoftCapExceeded: budget.userSoftCapExceeded,
        fallbackAllowed: config.aiImageEnableFallback
      },
      needsClarification,
      clarificationQuestions: needsClarification
        ? ['Please confirm portion sizes for the foods in this photo.']
        : [],
      parseDurationMs: roundedDurationMs,
      loggedAt: loggedAt.toISOString(),
      confidence: parsedImage.result.confidence,
      totals: parsedImage.result.totals,
      items: parsedImage.result.items,
      assumptions: parsedImage.result.assumptions,
      dietaryFlags: imageDietaryFlags,
      inputKind: 'image',
      extractedText: parsedImage.extractedText,
      imageMeta: {
        mimeType: body.mimeType,
        bytes: imageBytes
      },
      visionModel: parsedImage.model,
      visionFallbackUsed: parsedImage.fallbackUsed
    });
  } catch (err) {
    if (err && typeof err === 'object' && 'retryAfterSeconds' in err) {
      const retryAfter = (err as { retryAfterSeconds?: unknown }).retryAfterSeconds;
      if (typeof retryAfter === 'number') {
        res.setHeader('Retry-After', String(retryAfter));
      }
    }
    next(err);
  }
});

router.post('/', async (req, res, next) => {
  // SSE streaming path — when client sends Accept: text/event-stream
  if (req.headers.accept?.includes('text/event-stream')) {
    const startedAt = process.hrtime.bigint();
    try {
      const body = parseSchema.parse(req.body);
      const loggedAt = new Date(body.loggedAt);
      if (Number.isNaN(loggedAt.valueOf())) {
        throw new ApiError(400, 'INVALID_INPUT', 'Invalid loggedAt timestamp');
      }

      const auth = res.locals.auth as { userId: string; authProvider?: string; email?: string | null };
      await assertLoggedAtNotInFutureForUser(auth.userId, loggedAt);
      const rawAcceptLanguage = req.header('accept-language');
      const locale = rawAcceptLanguage ? rawAcceptLanguage.split(',')[0]?.trim() || null : null;
      const parseRequestId = res.locals.requestId as string;

      // Set up SSE headers
      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');
      res.setHeader('X-Accel-Buffering', 'no'); // Disable nginx buffering
      res.flushHeaders();

      // Keep-alive ping every 15s to prevent proxy/client timeouts
      const keepAlive = setInterval(() => {
        if (!res.writableEnded) res.write(':ping\n\n');
      }, 15_000);

      // Detect client disconnect
      const abortController = new AbortController();
      req.on('close', () => abortController.abort());

      const orchestrated = await executePrimaryParseStreaming({
        text: body.text,
        requestId: parseRequestId,
        auth,
        locale,
        signal: abortController.signal,
        onItem: (item, index) => {
          if (!res.writableEnded && !abortController.signal.aborted) {
            res.write(`event: item\ndata: ${JSON.stringify({ index, ...item })}\n\n`);
          }
        }
      });

      clearInterval(keepAlive);

      if (abortController.signal.aborted || res.writableEnded) return;

      const parseDurationMs = Number(process.hrtime.bigint() - startedAt) / 1_000_000;
      const roundedDurationMs = Math.round(parseDurationMs * 10) / 10;
      const { result, route, cacheHit, fallbackUsed, fallbackModel, needsClarification, clarificationQuestions, budget, sourcesUsed, reasonCodes, dietaryFlags } = orchestrated;

      res.write(`event: done\ndata: ${JSON.stringify({
        requestId: parseRequestId,
        parseRequestId,
        parseVersion: config.parseVersion,
        route,
        cacheHit,
        sourcesUsed,
        fallbackUsed,
        fallbackModel,
        budget,
        needsClarification,
        clarificationQuestions,
        reasonCodes,
        parseDurationMs: roundedDurationMs,
        loggedAt: loggedAt.toISOString(),
        confidence: result.confidence,
        totals: result.totals,
        items: result.items,
        assumptions: [],
        dietaryFlags: dietaryFlags ?? []
      })}\n\n`);
      res.end();
    } catch (err) {
      if (!res.writableEnded) {
        const message = err instanceof Error ? err.message : 'Parse failed';
        res.write(`event: error\ndata: ${JSON.stringify({ message })}\n\n`);
        res.end();
      }
    }
    return;
  }

  // Non-streaming path (unchanged)
  const startedAt = process.hrtime.bigint();
  try {
    const body = parseSchema.parse(req.body);
    const loggedAt = new Date(body.loggedAt);
    if (Number.isNaN(loggedAt.valueOf())) {
      throw new ApiError(400, 'INVALID_INPUT', 'Invalid loggedAt timestamp');
    }

    const auth = res.locals.auth as { userId: string; authProvider?: string; email?: string | null };
    await assertLoggedAtNotInFutureForUser(auth.userId, loggedAt);
    const rawAcceptLanguage = req.header('accept-language');
    const locale = rawAcceptLanguage ? rawAcceptLanguage.split(',')[0]?.trim() || null : null;
    const parseRequestId = res.locals.requestId as string;
    const orchestrated = await executePrimaryParse({
      text: body.text,
      requestId: parseRequestId,
      auth,
      locale
    });

    const parseDurationMs = Number(process.hrtime.bigint() - startedAt) / 1_000_000;
    const roundedDurationMs = Math.round(parseDurationMs * 10) / 10;
    const {
      result,
      route,
      cacheHit,
      fallbackUsed,
      fallbackModel,
      needsClarification,
      clarificationQuestions,
      budget,
      cacheDebug,
      sourcesUsed,
      reasonCodes,
      dietaryFlags
    } =
      orchestrated;

    const retryAfterSeconds = reasonCodes.includes('gemini_circuit_open')
      ? getGeminiCircuitRetryAfterSeconds()
      : null;

    res.setHeader('x-parse-route', route);
    res.setHeader('x-parse-duration-ms', String(roundedDurationMs));
    res.setHeader('x-parse-cache', cacheHit ? 'hit' : 'miss');
    res.setHeader('x-parse-fallback', fallbackUsed ? 'used' : 'not_used');
    res.setHeader('x-parse-clarification', needsClarification ? 'needed' : 'not_needed');

    res.status(200).json({
      requestId: parseRequestId,
      parseRequestId,
      parseVersion: config.parseVersion,
      route,
      cacheHit,
      sourcesUsed,
      fallbackUsed,
      fallbackModel,
      budget,
      needsClarification,
      clarificationQuestions,
      reasonCodes,
      ...(retryAfterSeconds ? { retryAfterSeconds } : {}),
      parseDurationMs: roundedDurationMs,
      loggedAt: loggedAt.toISOString(),
      confidence: result.confidence,
      totals: result.totals,
      items: result.items,
      assumptions: [],
      dietaryFlags: dietaryFlags ?? [],
      ...(cacheDebug ? { cacheDebug } : {})
    });
  } catch (err) {
    if (
      err &&
      typeof err === 'object' &&
      'retryAfterSeconds' in err &&
      typeof (err as { retryAfterSeconds?: unknown }).retryAfterSeconds === 'number'
    ) {
      res.setHeader('Retry-After', String((err as { retryAfterSeconds: number }).retryAfterSeconds));
    }
    next(err);
  }
});

router.post('/escalate', async (req, res, next) => {
  const startedAt = process.hrtime.bigint();
  try {
    if (!config.aiEscalationEnabled) {
      throw new ApiError(403, 'ESCALATION_DISABLED', 'Escalation is disabled');
    }

    const body = escalateSchema.parse(req.body);
    const loggedAt = new Date(body.loggedAt);
    if (Number.isNaN(loggedAt.valueOf())) {
      throw new ApiError(400, 'INVALID_INPUT', 'Invalid loggedAt timestamp');
    }

    const userId = res.locals.auth.userId as string;
    await assertLoggedAtNotInFutureForUser(userId, loggedAt);
    const requestId = res.locals.requestId as string;
    const budgetBefore = await getBudgetSnapshotForUser({
      userId,
      dailyBudgetUsd: config.aiDailyBudgetUsd,
      userSoftCapUsd: config.aiUserSoftCapUsd
    });
    const escalationAllowed = budgetBefore.globalUsedTodayUsd + config.aiEscalationCostUsd <= config.aiDailyBudgetUsd;
    if (!escalationAllowed) {
      throw new ApiError(429, 'BUDGET_EXCEEDED', 'Daily AI budget exceeded for escalation');
    }

    const parseRequest = await getParseRequestForUser(userId, body.parseRequestId);
    if (!parseRequest) {
      throw new ApiError(422, 'INVALID_PARSE_REFERENCE', 'Unknown parseRequestId');
    }
    if (isParseRequestStale(parseRequest)) {
      throw new ApiError(422, 'INVALID_PARSE_REFERENCE', 'Stale parseRequestId');
    }
    if (parseRequest.parseVersion !== config.parseVersion) {
      throw new ApiError(422, 'INVALID_PARSE_REFERENCE', 'parseRequestId parseVersion mismatch');
    }
    if (!parseRequest.needsClarification) {
      throw new ApiError(409, 'ESCALATION_NOT_REQUIRED', 'Primary parse does not require escalation');
    }

    const escalation = await runEscalationParse(parseRequest.rawText, {
      modelName: config.aiEscalationModelName,
      estimatedCostUsd: config.aiEscalationCostUsd
    });

    const budget = await recordAiCostWithBudgetGuard({
      userId,
      requestId,
      feature: 'escalation',
      model: escalation.model,
      inputTokens: escalation.inputTokens,
      outputTokens: escalation.outputTokens,
      estimatedCostUsd: escalation.estimatedCostUsd,
      dailyBudgetUsd: config.aiDailyBudgetUsd,
      userSoftCapUsd: config.aiUserSoftCapUsd
    });

    const parseDurationMs = Number(process.hrtime.bigint() - startedAt) / 1_000_000;
    const roundedDurationMs = Math.round(parseDurationMs * 10) / 10;

    res.setHeader('x-parse-route', 'escalation');
    res.setHeader('x-parse-duration-ms', String(roundedDurationMs));
    res.setHeader('x-parse-escalation', 'used');

    res.status(200).json({
      requestId,
      parseRequestId: parseRequest.requestId,
      parseVersion: parseRequest.parseVersion,
      route: 'escalation',
      sourcesUsed: collectSourcesUsed(escalation.result.items, 'gemini', false),
      escalationUsed: true,
      model: escalation.model,
      budget: {
        dailyLimitUsd: budget.dailyBudgetUsd,
        dailyUsedTodayUsd: Math.round(budget.globalUsedTodayUsd * 1000) / 1000,
        userSoftCapUsd: budget.userSoftCapUsd,
        userUsedTodayUsd: Math.round(budget.userUsedTodayUsd * 1000) / 1000,
        userSoftCapExceeded: budget.userSoftCapExceeded,
        escalationAllowed
      },
      parseDurationMs: roundedDurationMs,
      loggedAt: loggedAt.toISOString(),
      confidence: escalation.result.confidence,
      totals: escalation.result.totals,
      items: escalation.result.items,
      assumptions: []
    });
  } catch (err) {
    next(err);
  }
});

export default router;
