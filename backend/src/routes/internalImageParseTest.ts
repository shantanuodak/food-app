import { Router } from 'express';
import { z } from 'zod';
import { config } from '../config.js';
import { ApiError } from '../utils/errors.js';
import { parseImageWithGemini } from '../services/imageParseService.js';

const router = Router();

const supportedImageMimeTypes = new Set(['image/jpeg', 'image/png', 'image/heic']);

const imageParseTestSchema = z.object({
  imageBase64: z.string().trim().min(1),
  mimeType: z.string().trim().min(1).max(100),
  contextNote: z.string().trim().max(240).optional()
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

    const parsed = await parseImageWithGemini({
      mimeType: body.mimeType,
      dataBase64: body.imageBase64,
      contextNote: body.contextNote
    });

    const parseDurationMs = Number(process.hrtime.bigint() - startedAt) / 1_000_000;

    res.status(200).json({
      ok: true,
      parseDurationMs: Math.round(parseDurationMs * 10) / 10,
      inputKind: 'image',
      imageMeta: {
        mimeType: body.mimeType,
        bytes: imageBytes
      },
      model: parsed.model,
      fallbackUsed: parsed.fallbackUsed,
      lowConfidenceAccepted: parsed.lowConfidenceAccepted,
      confidence: parsed.result.confidence,
      extractedText: parsed.extractedText,
      totals: parsed.result.totals,
      items: parsed.result.items,
      assumptions: parsed.result.assumptions,
      usageEvents: parsed.usageEvents.map((event) => ({
        feature: event.feature,
        model: event.usage.model,
        inputTokens: event.usage.inputTokens,
        outputTokens: event.usage.outputTokens,
        estimatedCostUsd: event.estimatedCostUsd
      }))
    });
  } catch (err) {
    next(err);
  }
});

export default router;
