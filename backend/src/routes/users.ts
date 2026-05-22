import { Router } from 'express';
import { z } from 'zod';
import { ensureUserExists, getUserDisplayName, updateUserDisplayName } from '../services/userService.js';

const router = Router();

// Bug 2 (2026-05-22): editable display name on the Account screen. Apple
// Sign In only returns the user's full name on first sign-in, so testers
// like Tanmay end up seeing "Name: N" once the cached name drops. This
// route is the only path that can flip an already-set display_name —
// ensureUserExists uses COALESCE(NULLIF(...)) so it can NEVER overwrite a
// name the user just typed.
//
// Trim + 80 char cap matches the column shape and keeps the UI predictable.
// Empty after trim is allowed (clears the field; UI falls back to email
// prefix). Profanity / uniqueness checks are intentionally out of scope —
// see the Bug 2 task description in the session prompt.
const updateMeSchema = z.object({
  displayName: z.string().max(80)
});

router.patch('/me', async (req, res, next) => {
  try {
    const auth = res.locals.auth as { userId: string; authProvider?: string; email?: string | null };
    const body = updateMeSchema.parse(req.body);

    // Make sure the row exists before UPDATE — otherwise a brand-new user
    // who hasn't completed onboarding yet would get a silent no-op.
    await ensureUserExists(auth.userId, {
      authProvider: auth.authProvider,
      email: auth.email
    });

    const persisted = await updateUserDisplayName(auth.userId, body.displayName);
    res.status(200).json({ displayName: persisted });
  } catch (err) {
    next(err);
  }
});

router.get('/me', async (req, res, next) => {
  try {
    const auth = res.locals.auth as { userId: string };
    const displayName = await getUserDisplayName(auth.userId);
    res.status(200).json({ displayName });
  } catch (err) {
    next(err);
  }
});

export default router;
