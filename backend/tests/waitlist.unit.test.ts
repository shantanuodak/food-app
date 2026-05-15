import express from 'express';
import request from 'supertest';
import { beforeEach, describe, expect, test, vi } from 'vitest';

vi.mock('../src/services/waitlistService.js', () => ({
  saveWaitlistSignup: vi.fn()
}));

const { saveWaitlistSignup } = await import('../src/services/waitlistService.js');
const { default: waitlistRoutes } = await import('../src/routes/waitlist.js');

function createTestApp() {
  const app = express();
  app.use(express.json());
  app.use('/v1/waitlist', waitlistRoutes);
  app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    if (err instanceof Error && err.name === 'ZodError') {
      res.status(400).json({ code: 'VALIDATION_ERROR' });
      return;
    }
    res.status(500).json({ code: 'INTERNAL_ERROR' });
  });
  return app;
}

describe('waitlist route', () => {
  beforeEach(() => {
    vi.mocked(saveWaitlistSignup).mockReset();
  });

  test('saves a public website waitlist signup', async () => {
    vi.mocked(saveWaitlistSignup).mockResolvedValue({
      id: 'signup-1',
      email: 'person@example.com',
      source: 'food-app-website',
      createdAt: '2026-05-15T12:00:00.000Z',
      alreadyJoined: false
    });

    const response = await request(createTestApp())
      .post('/v1/waitlist')
      .set('user-agent', 'unit-test-agent')
      .send({ email: ' Person@Example.com ', source: 'food-app-website' });

    expect(response.status).toBe(201);
    expect(response.headers['access-control-allow-origin']).toBe('*');
    expect(response.body).toEqual({
      id: 'signup-1',
      createdAt: '2026-05-15T12:00:00.000Z',
      alreadyJoined: false
    });
    expect(saveWaitlistSignup).toHaveBeenCalledWith({
      email: 'Person@Example.com',
      source: 'food-app-website',
      userAgent: 'unit-test-agent'
    });
  });

  test('returns alreadyJoined for duplicate emails', async () => {
    vi.mocked(saveWaitlistSignup).mockResolvedValue({
      id: 'signup-1',
      email: 'person@example.com',
      source: 'food-app-website',
      createdAt: '2026-05-15T12:00:00.000Z',
      alreadyJoined: true
    });

    const response = await request(createTestApp())
      .post('/v1/waitlist')
      .send({ email: 'person@example.com' });

    expect(response.status).toBe(201);
    expect(response.body.alreadyJoined).toBe(true);
  });

  test('rejects invalid email input', async () => {
    const response = await request(createTestApp())
      .post('/v1/waitlist')
      .send({ email: 'not-an-email' });

    expect(response.status).toBe(400);
    expect(saveWaitlistSignup).not.toHaveBeenCalled();
  });

  test('answers CORS preflight for hosted website submissions', async () => {
    const response = await request(createTestApp())
      .options('/v1/waitlist')
      .set('origin', 'https://example.com')
      .set('access-control-request-method', 'POST');

    expect(response.status).toBe(204);
    expect(response.headers['access-control-allow-origin']).toBe('*');
    expect(response.headers['access-control-allow-methods']).toBe('POST, OPTIONS');
  });
});
