import { Router } from 'express';
import { z } from 'zod';
import { recordAuthDiagnosticEvents } from '../services/authDiagnosticService.js';

const metadataSchema = z.record(
  z.string().trim().min(1).max(80),
  z.union([z.string(), z.number(), z.boolean(), z.null()]).transform((value) => String(value ?? ''))
).default({});

const eventSchema = z.object({
  clientEventId: z.string().uuid(),
  eventName: z.string().trim().min(1).max(80),
  occurredAt: z.string().datetime(),
  appLaunchId: z.string().uuid().nullable().optional(),
  clientBuild: z.string().trim().max(40).nullable().optional(),
  appVersion: z.string().trim().max(40).nullable().optional(),
  osVersion: z.string().trim().max(80).nullable().optional(),
  deviceModel: z.string().trim().max(80).nullable().optional(),
  provider: z.enum(['apple', 'google']).nullable().optional(),
  userIdHint: z.string().uuid().nullable().optional(),
  metadata: metadataSchema
});

const batchSchema = z.object({
  events: z.array(eventSchema).max(50)
});

const router = Router();

router.post('/events', async (req, res, next) => {
  try {
    const auth = res.locals.auth as { userId: string };
    const body = batchSchema.parse(req.body);
    const accepted = await recordAuthDiagnosticEvents(
      auth.userId,
      body.events.map((event) => ({
        ...event,
        occurredAt: new Date(event.occurredAt)
      }))
    );
    res.status(202).json({ status: 'accepted', accepted });
  } catch (error) {
    next(error);
  }
});

export default router;
