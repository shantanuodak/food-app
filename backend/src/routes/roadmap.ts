import { Router } from 'express';
import { z } from 'zod';
import { config } from '../config.js';
import { ApiError } from '../utils/errors.js';
import {
  createRoadmapItem,
  groupRoadmapItems,
  listRoadmapItems,
  reorderRoadmapItems,
  updateRoadmapItem
} from '../services/roadmapService.js';

function requireInternalKey(key: string | undefined): void {
  if (!config.internalMetricsKey) {
    throw new ApiError(503, 'INTERNAL_METRICS_DISABLED', 'Internal metrics key is not configured');
  }
  if (!key || key !== config.internalMetricsKey) {
    throw new ApiError(403, 'FORBIDDEN', 'Invalid internal metrics key');
  }
}

const itemSchema = z.object({
  itemType: z.enum(['fix', 'feature']),
  title: z.string().trim().min(1).max(160),
  description: z.string().trim().max(1200).default(''),
  status: z.enum(['not_started', 'in_progress', 'done']).default('not_started'),
  releaseVersion: z.string().trim().max(40).nullable().optional(),
  targetDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  targetDateLabel: z.string().trim().max(40).optional().default('TBD'),
  displayOrder: z.coerce.number().int().min(0).max(100000).optional().default(0),
  isVisible: z.boolean().optional().default(true),
  sourceFeedbackId: z.string().uuid().nullable().optional()
});

const reorderSchema = z.object({
  itemType: z.enum(['fix', 'feature']),
  ids: z.array(z.string().uuid()).min(1).max(200)
});

function normalizeItemInput(raw: unknown) {
  const parsed = itemSchema.parse(raw);
  return {
    ...parsed,
    releaseVersion: parsed.releaseVersion || null,
    targetDate: parsed.targetDate || null,
    targetDateLabel: parsed.targetDateLabel || 'TBD',
    sourceFeedbackId: parsed.sourceFeedbackId || null
  };
}

export const publicRouter = Router();

publicRouter.get('/', async (_req, res, next) => {
  try {
    const grouped = groupRoadmapItems(await listRoadmapItems({ visibleOnly: true }));
    res.status(200).json(grouped);
  } catch (err) {
    next(err);
  }
});

export const adminRouter = Router();

adminRouter.get('/', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    const items = await listRoadmapItems();
    res.status(200).json({ items, ...groupRoadmapItems(items) });
  } catch (err) {
    next(err);
  }
});

adminRouter.post('/', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    const item = await createRoadmapItem(normalizeItemInput(req.body));
    res.status(201).json({ item });
  } catch (err) {
    next(err);
  }
});

adminRouter.patch('/reorder', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    const input = reorderSchema.parse(req.body);
    const items = await reorderRoadmapItems(input.itemType, input.ids);
    res.status(200).json({ items, ...groupRoadmapItems(items) });
  } catch (err) {
    next(err);
  }
});

adminRouter.patch('/:id', async (req, res, next) => {
  try {
    requireInternalKey(req.header('x-internal-metrics-key'));
    const id = z.string().uuid().parse(req.params.id);
    const item = await updateRoadmapItem(id, normalizeItemInput(req.body));
    if (!item) {
      throw new ApiError(404, 'ROADMAP_ITEM_NOT_FOUND', 'Roadmap item not found');
    }
    res.status(200).json({ item });
  } catch (err) {
    next(err);
  }
});
