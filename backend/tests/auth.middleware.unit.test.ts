import { afterEach, describe, expect, test, vi } from 'vitest';
import { createHmac, generateKeyPairSync, sign, type KeyObject } from 'node:crypto';

const baseEnv = { ...process.env };

function encodeBase64Url(input: string): string {
  return Buffer.from(input, 'utf8')
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function encodeBase64UrlBuffer(input: Buffer): string {
  return input
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function signHs256(unsignedToken: string, secret: string): string {
  return createHmac('sha256', secret)
    .update(unsignedToken)
    .digest('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function buildSupabaseJwt(input: {
  secret: string;
  sub: string;
  aud?: string;
  iss?: string;
  expOffsetSeconds?: number;
}): string {
  const header = encodeBase64Url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const payload = encodeBase64Url(
    JSON.stringify({
      sub: input.sub,
      aud: input.aud || 'authenticated',
      iss: input.iss || 'https://example.supabase.co/auth/v1',
      exp: Math.floor(Date.now() / 1000) + (input.expOffsetSeconds || 600)
    })
  );
  const unsignedToken = `${header}.${payload}`;
  const signature = signHs256(unsignedToken, input.secret);
  return `${unsignedToken}.${signature}`;
}

function buildEs256Jwt(input: {
  privateKey: KeyObject;
  kid: string;
  sub: string;
  aud?: string;
  iss?: string;
  expOffsetSeconds?: number;
}): string {
  const header = encodeBase64Url(JSON.stringify({ alg: 'ES256', typ: 'JWT', kid: input.kid }));
  const payload = encodeBase64Url(
    JSON.stringify({
      sub: input.sub,
      aud: input.aud || 'authenticated',
      iss: input.iss || 'https://example.supabase.co/auth/v1',
      exp: Math.floor(Date.now() / 1000) + (input.expOffsetSeconds || 600)
    })
  );
  const unsignedToken = `${header}.${payload}`;
  const signature = sign('sha256', Buffer.from(unsignedToken, 'utf8'), {
    key: input.privateKey,
    dsaEncoding: 'ieee-p1363'
  });
  return `${unsignedToken}.${encodeBase64UrlBuffer(signature)}`;
}

async function runAuth(headerValue: string | undefined): Promise<{ error: unknown; auth: unknown }> {
  const { authRequired } = await import('../src/middleware/auth.js');
  const req = {
    header: (name: string) => (name.toLowerCase() === 'authorization' ? headerValue : undefined)
  };
  const res = { locals: { requestId: 'req-test' } };

  let forwardedError: unknown = null;
  await new Promise<void>((resolve) => {
    authRequired(req as never, res as never, (err?: unknown) => {
      forwardedError = err || null;
      resolve();
    });
  });

  return { error: forwardedError, auth: res.locals.auth };
}

afterEach(() => {
  vi.resetModules();
  vi.unstubAllGlobals();
  process.env = { ...baseEnv };
});

describe('auth middleware', () => {
  test('accepts dev bearer token in dev mode', async () => {
    process.env.AUTH_MODE = 'dev';
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const result = await runAuth('Bearer dev-11111111-1111-1111-1111-111111111111');
    expect(result.error).toBeNull();
    expect(result.auth).toMatchObject({
      userId: '11111111-1111-1111-1111-111111111111',
      authProvider: 'dev'
    });
  });

  test('accepts valid Supabase JWT in supabase mode', async () => {
    process.env.AUTH_MODE = 'supabase';
    process.env.SUPABASE_JWT_SECRET = 'test-secret';
    process.env.SUPABASE_JWT_ISSUER = 'https://example.supabase.co/auth/v1';
    process.env.SUPABASE_JWT_AUDIENCE = 'authenticated';
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const token = buildSupabaseJwt({
      secret: 'test-secret',
      sub: '22222222-2222-2222-2222-222222222222',
      aud: 'authenticated',
      iss: 'https://example.supabase.co/auth/v1'
    });

    const result = await runAuth(`Bearer ${token}`);
    expect(result.error).toBeNull();
    expect(result.auth).toMatchObject({
      userId: '22222222-2222-2222-2222-222222222222',
      authProvider: 'supabase'
    });
  });

  test('rejects invalid Supabase JWT signature', async () => {
    process.env.AUTH_MODE = 'supabase';
    process.env.SUPABASE_JWT_SECRET = 'expected-secret';
    process.env.SUPABASE_JWT_ISSUER = 'https://example.supabase.co/auth/v1';
    process.env.SUPABASE_JWT_AUDIENCE = 'authenticated';
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const token = buildSupabaseJwt({
      secret: 'different-secret',
      sub: '33333333-3333-3333-3333-333333333333',
      aud: 'authenticated',
      iss: 'https://example.supabase.co/auth/v1'
    });

    const result = await runAuth(`Bearer ${token}`);
    expect(result.auth).toBeUndefined();
    expect(result.error).toMatchObject({
      statusCode: 401,
      code: 'UNAUTHORIZED'
    });
  });

  test('accepts valid ES256 Supabase JWT via JWKS', async () => {
    process.env.AUTH_MODE = 'supabase';
    process.env.SUPABASE_JWT_SECRET = '';
    process.env.SUPABASE_JWT_ISSUER = 'https://example.supabase.co/auth/v1';
    process.env.SUPABASE_JWT_AUDIENCE = 'authenticated';
    process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';

    const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
    const publicJwk = publicKey.export({ format: 'jwk' }) as Record<string, string>;
    const kid = 'es256-test-key';

    const fetchMock = vi.fn(async () => ({
      ok: true,
      json: async () => ({
        keys: [
          {
            ...publicJwk,
            kid,
            use: 'sig',
            alg: 'ES256'
          }
        ]
      })
    }));
    vi.stubGlobal('fetch', fetchMock as unknown as typeof fetch);

    const token = buildEs256Jwt({
      privateKey,
      kid,
      sub: '44444444-4444-4444-4444-444444444444',
      aud: 'authenticated',
      iss: 'https://example.supabase.co/auth/v1'
    });

    const result = await runAuth(`Bearer ${token}`);
    expect(result.error).toBeNull();
    expect(result.auth).toMatchObject({
      userId: '44444444-4444-4444-4444-444444444444',
      authProvider: 'supabase'
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});
