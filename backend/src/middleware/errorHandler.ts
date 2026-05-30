import type { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { ApiError } from '../utils/errors.js';

export function notFoundHandler(_req: Request, _res: Response, next: NextFunction): void {
  next(new ApiError(404, 'NOT_FOUND', 'Endpoint not found'));
}

export function errorHandler(err: unknown, _req: Request, res: Response, _next: NextFunction): void {
  const requestId = res.locals.requestId || 'unknown';

  if (err instanceof ZodError) {
    res.status(400).json({
      error: {
        code: 'INVALID_INPUT',
        message: err.issues[0]?.message || 'Invalid request payload',
        requestId
      }
    });
    return;
  }

  if (err instanceof ApiError) {
    const retryAfterSeconds = (err as ApiError & { retryAfterSeconds?: number }).retryAfterSeconds;
    const hasRetryAfter = typeof retryAfterSeconds === 'number' && Number.isFinite(retryAfterSeconds) && retryAfterSeconds > 0;
    if (hasRetryAfter) {
      res.setHeader('Retry-After', String(Math.ceil(retryAfterSeconds!)));
    }
    res.status(err.statusCode).json({
      error: {
        code: err.code,
        message: err.message,
        requestId,
        ...(hasRetryAfter ? { retryAfterSeconds: Math.ceil(retryAfterSeconds!) } : {})
      }
    });
    return;
  }

  console.error('Unhandled error', { requestId, err });
  res.status(500).json({
    error: {
      code: 'INTERNAL_ERROR',
      message: 'Unexpected server error',
      requestId
    }
  });
}
