import { Router } from 'express';
import { z } from 'zod';
import { saveWaitlistSignup } from '../services/waitlistService.js';

const waitlistSchema = z.object({
  email: z.string().trim().email().max(320),
  source: z.string().trim().min(1).max(80).optional().default('website')
});

function applyWaitlistCors(res: import('express').Response): void {
  // Public, no-cookie endpoint for the marketing site. Keep this route
  // intentionally broad so Vercel/Netlify/custom-domain hosting works without
  // another backend deploy.
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Access-Control-Max-Age', '86400');
}

const router = Router();

router.options('/', (_req, res) => {
  applyWaitlistCors(res);
  res.status(204).end();
});

router.post('/', async (req, res, next) => {
  try {
    applyWaitlistCors(res);
    const body = waitlistSchema.parse(req.body);
    const signup = await saveWaitlistSignup({
      email: body.email,
      source: body.source,
      userAgent: req.header('user-agent')?.slice(0, 500) ?? null
    });

    res.status(201).json({
      id: signup.id,
      createdAt: signup.createdAt,
      alreadyJoined: signup.alreadyJoined
    });
  } catch (err) {
    next(err);
  }
});

export default router;
