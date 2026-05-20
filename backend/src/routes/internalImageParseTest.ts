import { Router } from 'express';
import { z } from 'zod';
import { config } from '../config.js';
import { ApiError } from '../utils/errors.js';
import { parseImageWithGemini, type ImageParseDebugEvent, type ImageParseServiceResult } from '../services/imageParseService.js';
import { routeImageParse } from '../services/imageParse/router.js';
import type { Cuisine } from '../services/imageParse/cuisineClassifier.js';

const router = Router();

const supportedImageMimeTypes = new Set(['image/jpeg', 'image/png', 'image/heic']);

type InternalImageParseResult = ImageParseServiceResult & {
  laneSource?: string;
  laneLatencyMs?: number;
};

const imageParseTestSchema = z.object({
  imageBase64: z.string().trim().min(1),
  mimeType: z.string().trim().min(1).max(100),
  contextNote: z.string().trim().max(240).optional(),
  lane: z.enum(['barcode', 'label', 'vision']).optional().default('vision'),
  barcode: z.string().trim().regex(/^\d{8,14}$/).optional(),
  symbology: z.string().trim().max(32).optional(),
  ocrText: z.string().trim().min(1).max(4000).optional(),
  userLocale: z.string().trim().max(40).optional(),
  recentCuisines: z.array(z.enum(['indian', 'us', 'western', 'eastAsian', 'mediterranean', 'latin', 'generic'])).max(14).optional()
});

function requireInternalKey(key: string | undefined): void {
  if (!config.internalMetricsKey) {
    throw new ApiError(503, 'INTERNAL_METRICS_DISABLED', 'Internal metrics key is not configured');
  }
  if (!key || key !== config.internalMetricsKey) {
    throw new ApiError(403, 'FORBIDDEN', 'Invalid internal metrics key');
  }
}

router.post('/image-parse', async (req, res, next) => {
  const startedAt = process.hrtime.bigint();
  const debugEvents: ImageParseDebugEvent[] = [];
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    if (!config.internalImageParseTestEnabled) {
      throw new ApiError(403, 'INTERNAL_IMAGE_PARSE_TEST_DISABLED', 'Internal image parse testing is disabled');
    }

    const body = imageParseTestSchema.parse(req.body ?? {});
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

    const useLaneRouter = config.aiImageLaneRouterEnabled || body.lane !== 'vision';
    const parsed: InternalImageParseResult =
      useLaneRouter
        ? await routeImageParse({
            lane: body.lane,
            barcode: body.barcode ? { code: body.barcode, symbology: body.symbology } : undefined,
            ocrText: body.ocrText,
            image: {
              mimeType: body.mimeType,
              dataBase64: body.imageBase64,
              contextNote: body.contextNote,
              debugEvents
            },
            contextNote: body.contextNote,
            userLocale: body.userLocale,
            recentCuisines: body.recentCuisines as Cuisine[] | undefined
          })
        : await parseImageWithGemini({
            mimeType: body.mimeType,
            dataBase64: body.imageBase64,
            contextNote: body.contextNote,
            debugEvents
          });

    const parseDurationMs = Number(process.hrtime.bigint() - startedAt) / 1_000_000;

    res.status(200).json({
      ok: true,
      parseDurationMs: Math.round(parseDurationMs * 10) / 10,
      inputKind: 'image',
      imageMeta: {
        mimeType: body.mimeType,
        bytes: imageBytes,
        orchestratorVersion: parsed.orchestratorVersion,
        coverage: parsed.coverage ?? null
      },
      model: parsed.model,
      fallbackUsed: parsed.fallbackUsed,
      lowConfidenceAccepted: parsed.lowConfidenceAccepted,
      orchestratorVersion: parsed.orchestratorVersion,
      parseLaneUsed: body.lane,
      parseLaneSource: useLaneRouter
        ? body.lane === 'vision'
          ? 'lane_router'
          : parsed.laneSource ?? body.lane
        : 'legacy_image',
      parseLaneLatencyMs: parsed.laneLatencyMs ?? Math.round(parseDurationMs),
      cuisineUsed: parsed.cuisine?.cuisine ?? parsed.coverage?.cuisineHints?.[0] ?? null,
      cuisineSource: parsed.cuisine?.source ?? null,
      cuisineConfidence: parsed.cuisine?.confidence ?? null,
      cuisineMatchedKeywords: parsed.cuisine?.matchedKeywords ?? [],
      coverage: parsed.coverage ?? null,
      confidence: parsed.result.confidence,
      extractedText: parsed.extractedText,
      totals: parsed.result.totals,
      items: parsed.result.items,
      assumptions: parsed.result.assumptions,
      debugEvents,
      usageEvents: parsed.usageEvents.map((event) => ({
        feature: event.feature,
        model: event.usage.model,
        inputTokens: event.usage.inputTokens,
        outputTokens: event.usage.outputTokens,
        estimatedCostUsd: event.estimatedCostUsd
      }))
    });
  } catch (err) {
    if (err instanceof ApiError) {
      const parseDurationMs = Number(process.hrtime.bigint() - startedAt) / 1_000_000;
      res.status(err.statusCode).json({
        error: {
          code: err.code,
          message: err.message,
          requestId: res.locals.requestId
        },
        diagnostics: {
          parseDurationMs: Math.round(parseDurationMs * 10) / 10,
          debugEvents
        }
      });
      return;
    }
    next(err);
  }
});

export default router;
