import type { Request, Response, NextFunction } from 'express';
import { createHmac, createPublicKey, timingSafeEqual, verify as verifySignature } from 'node:crypto';
import { config } from '../config.js';
import { runWithDbAuthContext } from '../db.js';
import { ApiError } from '../utils/errors.js';
import type { AuthContext } from '../types.js';
import { isAdminEmail } from '../services/adminFeatureFlagsService.js';

const SUPABASE_JWKS_CACHE_TTL_MS = 5 * 60 * 1000;
const SUPABASE_JWKS_ERROR_TTL_MS = 30 * 1000;

type JwtPayload = {
  sub?: unknown;
  exp?: unknown;
  nbf?: unknown;
  iat?: unknown;
  iss?: unknown;
  aud?: unknown;
  email?: unknown;
};

type JwtHeader = {
  alg?: unknown;
  kid?: unknown;
};

type ParsedJwt = {
  encodedHeader: string;
  encodedPayload: string;
  header: JwtHeader;
  payload: JwtPayload;
  signature: Buffer;
};

type SupabaseJwk = {
  kid?: string;
  alg?: string;
  use?: string;
  kty?: string;
  crv?: string;
  [key: string]: unknown;
};

let supabaseJwksCache: { keys: SupabaseJwk[]; expiresAt: number } = {
  keys: [],
  expiresAt: 0
};
let supabaseJwksRequestInFlight: Promise<SupabaseJwk[]> | null = null;

function isUuid(value: string): boolean {
  // Dev auth accepts any canonical UUID-like hex shape (8-4-4-4-12).
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

function decodeBase64Url(value: string): Buffer {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padding = (4 - (normalized.length % 4)) % 4;
  return Buffer.from(normalized + '='.repeat(padding), 'base64');
}

function parseJsonObject(value: Buffer): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(value.toString('utf8')) as unknown;
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? (parsed as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function parseJwt(token: string): ParsedJwt | null {
  const parts = token.split('.');
  if (parts.length !== 3) {
    return null;
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  let headerBuffer: Buffer;
  let payloadBuffer: Buffer;
  let signatureBuffer: Buffer;
  try {
    headerBuffer = decodeBase64Url(encodedHeader);
    payloadBuffer = decodeBase64Url(encodedPayload);
    signatureBuffer = decodeBase64Url(encodedSignature);
  } catch {
    return null;
  }

  const header = parseJsonObject(headerBuffer);
  const payload = parseJsonObject(payloadBuffer);
  if (!header || !payload) {
    return null;
  }

  return {
    encodedHeader,
    encodedPayload,
    header: header as JwtHeader,
    payload: payload as JwtPayload,
    signature: signatureBuffer
  };
}

function verifyHs256Signature(parsed: ParsedJwt): boolean {
  if (!config.supabaseJwtSecret) {
    return false;
  }

  const unsigned = `${parsed.encodedHeader}.${parsed.encodedPayload}`;
  const expectedSignature = createHmac('sha256', config.supabaseJwtSecret).update(unsigned).digest();
  if (parsed.signature.length !== expectedSignature.length) {
    return false;
  }

  return timingSafeEqual(parsed.signature, expectedSignature);
}

function compactTokenDebugSummary(token: string): string {
  const parsed = parseJwt(token);
  if (!parsed) {
    return 'token is not a valid JWT';
  }

  const alg = typeof parsed.header.alg === 'string' ? parsed.header.alg : '<missing>';
  const iss = typeof parsed.payload.iss === 'string' ? parsed.payload.iss : '<missing>';
  const aud = Array.isArray(parsed.payload.aud)
    ? parsed.payload.aud.join('|')
    : typeof parsed.payload.aud === 'string'
      ? parsed.payload.aud
      : '<missing>';
  const sub = typeof parsed.payload.sub === 'string' ? parsed.payload.sub : '<missing>';

  return `alg=${alg} iss=${iss} aud=${aud} sub=${sub} expected_iss=${config.supabaseJwtIssuer} expected_aud=${config.supabaseJwtAudience}`;
}

function asString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function isSupabaseJwk(value: unknown): value is SupabaseJwk {
  if (!isRecord(value)) {
    return false;
  }

  if (typeof value.kty !== 'string') {
    return false;
  }

  if (value.kty === 'RSA') {
    if (typeof value.n !== 'string' || typeof value.e !== 'string') {
      return false;
    }
  } else if (value.kty === 'EC') {
    if (value.crv !== 'P-256') {
      return false;
    }
    if (typeof value.x !== 'string' || typeof value.y !== 'string') {
      return false;
    }
  } else {
    return false;
  }

  if (value.use !== undefined && typeof value.use !== 'string') {
    return false;
  }

  if (value.kid !== undefined && typeof value.kid !== 'string') {
    return false;
  }

  return true;
}

function resolveSupabaseJwksUrl(): string {
  const direct = config.supabaseJwksUrl.trim();
  if (direct) {
    return direct;
  }

  const issuer = config.supabaseJwtIssuer.trim();
  if (!issuer) {
    return '';
  }

  return `${issuer.replace(/\/+$/, '')}/.well-known/jwks.json`;
}

function hasSupabaseVerifierConfig(): boolean {
  return Boolean(config.supabaseJwtSecret) || Boolean(resolveSupabaseJwksUrl());
}

async function fetchSupabaseJwks(): Promise<SupabaseJwk[]> {
  const now = Date.now();
  if (supabaseJwksCache.expiresAt > now) {
    return supabaseJwksCache.keys;
  }

  if (supabaseJwksRequestInFlight) {
    return supabaseJwksRequestInFlight;
  }

  const jwksUrl = resolveSupabaseJwksUrl();
  if (!jwksUrl) {
    supabaseJwksCache = { keys: [], expiresAt: now + SUPABASE_JWKS_ERROR_TTL_MS };
    return [];
  }

  supabaseJwksRequestInFlight = (async () => {
    const controller = new AbortController();
    const timeoutHandle = setTimeout(() => controller.abort(), 4000);

    try {
      const response = await fetch(jwksUrl, {
        method: 'GET',
        headers: { accept: 'application/json' },
        signal: controller.signal
      });

      if (!response.ok) {
        supabaseJwksCache = {
          keys: [],
          expiresAt: Date.now() + SUPABASE_JWKS_ERROR_TTL_MS
        };
        return [];
      }

      const json = (await response.json()) as unknown;
      const keys =
        isRecord(json) && Array.isArray(json.keys) ? json.keys.filter((entry) => isSupabaseJwk(entry)) : [];

      supabaseJwksCache = {
        keys,
        expiresAt: Date.now() + (keys.length > 0 ? SUPABASE_JWKS_CACHE_TTL_MS : SUPABASE_JWKS_ERROR_TTL_MS)
      };
      return keys;
    } catch {
      supabaseJwksCache = {
        keys: [],
        expiresAt: Date.now() + SUPABASE_JWKS_ERROR_TTL_MS
      };
      return [];
    } finally {
      clearTimeout(timeoutHandle);
      supabaseJwksRequestInFlight = null;
    }
  })();

  return supabaseJwksRequestInFlight;
}

async function verifyRs256Signature(parsed: ParsedJwt): Promise<boolean> {
  const keys = await fetchSupabaseJwks();
  if (keys.length === 0) {
    return false;
  }

  const tokenKid = asString(parsed.header.kid);
  const candidateKeys = tokenKid ? keys.filter((key) => key.kid === tokenKid) : keys;
  if (candidateKeys.length === 0) {
    return false;
  }

  const unsigned = Buffer.from(`${parsed.encodedHeader}.${parsed.encodedPayload}`, 'utf8');

  for (const key of candidateKeys) {
    try {
      if (key.use && key.use !== 'sig') {
        continue;
      }
      if (key.kty !== 'RSA') {
        continue;
      }
      if (key.alg && key.alg !== 'RS256') {
        continue;
      }

      const keyInput = { key: key as unknown, format: 'jwk' as const } as Parameters<typeof createPublicKey>[0];
      const publicKey = createPublicKey(keyInput);
      const isValid = verifySignature('RSA-SHA256', unsigned, publicKey, parsed.signature);
      if (isValid) {
        return true;
      }
    } catch {
      // Ignore invalid keys and continue trying remaining candidates.
    }
  }

  return false;
}

function trimLeadingZeroBytes(value: Buffer): Buffer {
  let offset = 0;
  while (offset < value.length - 1 && value[offset] === 0) {
    offset += 1;
  }
  return value.subarray(offset);
}

function derLengthBytes(length: number): Buffer {
  if (length < 128) {
    return Buffer.from([length]);
  }

  const bytes: number[] = [];
  let remaining = length;
  while (remaining > 0) {
    bytes.unshift(remaining & 0xff);
    remaining >>= 8;
  }
  return Buffer.from([0x80 | bytes.length, ...bytes]);
}

function joseEcdsaSignatureToDer(signature: Buffer, componentSize: number): Buffer | null {
  if (signature.length !== componentSize * 2) {
    return null;
  }

  const rRaw = signature.subarray(0, componentSize);
  const sRaw = signature.subarray(componentSize, componentSize * 2);

  const rTrimmed = trimLeadingZeroBytes(rRaw);
  const sTrimmed = trimLeadingZeroBytes(sRaw);

  const r = rTrimmed[0] & 0x80 ? Buffer.concat([Buffer.from([0x00]), rTrimmed]) : rTrimmed;
  const s = sTrimmed[0] & 0x80 ? Buffer.concat([Buffer.from([0x00]), sTrimmed]) : sTrimmed;

  const rEntry = Buffer.concat([Buffer.from([0x02]), derLengthBytes(r.length), r]);
  const sEntry = Buffer.concat([Buffer.from([0x02]), derLengthBytes(s.length), s]);
  const sequence = Buffer.concat([rEntry, sEntry]);
  return Buffer.concat([Buffer.from([0x30]), derLengthBytes(sequence.length), sequence]);
}

async function verifyEs256Signature(parsed: ParsedJwt): Promise<boolean> {
  const keys = await fetchSupabaseJwks();
  if (keys.length === 0) {
    return false;
  }

  const tokenKid = asString(parsed.header.kid);
  const candidateKeys = tokenKid ? keys.filter((key) => key.kid === tokenKid) : keys;
  if (candidateKeys.length === 0) {
    return false;
  }

  const unsigned = Buffer.from(`${parsed.encodedHeader}.${parsed.encodedPayload}`, 'utf8');
  const derSignature = joseEcdsaSignatureToDer(parsed.signature, 32);
  if (!derSignature) {
    return false;
  }

  for (const key of candidateKeys) {
    try {
      if (key.use && key.use !== 'sig') {
        continue;
      }
      if (key.kty !== 'EC' || key.crv !== 'P-256') {
        continue;
      }
      if (key.alg && key.alg !== 'ES256') {
        continue;
      }

      const keyInput = { key: key as unknown, format: 'jwk' as const } as Parameters<typeof createPublicKey>[0];
      const publicKey = createPublicKey(keyInput);
      const isValid = verifySignature('sha256', unsigned, publicKey, derSignature);
      if (isValid) {
        return true;
      }
    } catch {
      // Ignore invalid keys and continue trying remaining candidates.
    }
  }

  return false;
}

async function verifySupabaseJwt(token: string): Promise<JwtPayload | null> {
  const parsed = parseJwt(token);
  if (!parsed) {
    return null;
  }

  const algorithm = asString(parsed.header.alg);
  if (algorithm === 'HS256') {
    return verifyHs256Signature(parsed) ? parsed.payload : null;
  }

  if (algorithm === 'RS256') {
    return (await verifyRs256Signature(parsed)) ? parsed.payload : null;
  }

  if (algorithm === 'ES256') {
    return (await verifyEs256Signature(parsed)) ? parsed.payload : null;
  }

  return null;
}

function isAudienceValid(value: unknown): boolean {
  if (!config.supabaseJwtAudience) {
    return true;
  }
  if (typeof value === 'string') {
    return value === config.supabaseJwtAudience;
  }
  if (Array.isArray(value)) {
    return value.some((entry) => entry === config.supabaseJwtAudience);
  }
  return false;
}

function validateSupabasePayload(payload: JwtPayload): { userId: string; email: string | null } | null {
  const userId = typeof payload.sub === 'string' ? payload.sub : '';
  if (!isUuid(userId)) {
    return null;
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  const leeway = Math.max(0, config.supabaseJwtClockSkewSeconds);
  const exp = typeof payload.exp === 'number' ? payload.exp : null;
  const nbf = typeof payload.nbf === 'number' ? payload.nbf : null;
  const iat = typeof payload.iat === 'number' ? payload.iat : null;

  if (exp !== null && exp + leeway < nowSeconds) {
    return null;
  }
  if (nbf !== null && nbf - leeway > nowSeconds) {
    return null;
  }
  if (iat !== null && iat - leeway > nowSeconds) {
    return null;
  }

  if (config.supabaseJwtIssuer) {
    if (typeof payload.iss !== 'string' || payload.iss !== config.supabaseJwtIssuer) {
      return null;
    }
  }

  if (!isAudienceValid(payload.aud)) {
    return null;
  }

  return {
    userId,
    email: typeof payload.email === 'string' ? payload.email : null
  };
}

function applyAuthContext(res: Response, context: Omit<AuthContext, 'requestId'>): void {
  res.locals.auth = {
    ...context,
    requestId: res.locals.requestId
  };
}

function tryDevAuth(token: string): Omit<AuthContext, 'requestId'> | null {
  if (config.authMode === 'supabase') {
    return null;
  }
  if (!token.startsWith(config.authBearerDevPrefix)) {
    return null;
  }

  const userId = token.slice(config.authBearerDevPrefix.length);
  if (!isUuid(userId)) {
    return null;
  }

  const email = `${userId}@dev.local`;
  return {
    userId,
    authProvider: 'dev',
    email,
    isAdmin: isAdminEmail(email)
  };
}

async function trySupabaseAuth(token: string): Promise<Omit<AuthContext, 'requestId'> | null> {
  if (config.authMode === 'dev') {
    return null;
  }

  const payload = await verifySupabaseJwt(token);
  if (!payload) {
    return null;
  }

  const validated = validateSupabasePayload(payload);
  if (!validated) {
    return null;
  }

  const email = validated.email;
  return {
    userId: validated.userId,
    authProvider: 'supabase',
    email,
    isAdmin: isAdminEmail(email)
  };
}

export function authRequired(req: Request, res: Response, next: NextFunction): void {
  void authRequiredAsync(req, res, next).catch((error) => {
    next(error);
  });
}

async function authRequiredAsync(req: Request, res: Response, next: NextFunction): Promise<void> {
  const authHeader = req.header('authorization');

  if (!authHeader?.startsWith('Bearer ')) {
    next(new ApiError(401, 'UNAUTHORIZED', 'Missing bearer token'));
    return;
  }

  const token = authHeader.slice('Bearer '.length).trim();
  if (!token) {
    next(new ApiError(401, 'UNAUTHORIZED', 'Missing bearer token'));
    return;
  }

  const devAuth = tryDevAuth(token);
  if (devAuth) {
    runWithDbAuthContext(devAuth, () => {
      applyAuthContext(res, devAuth);
      next();
    });
    return;
  }

  const supabaseAuth = await trySupabaseAuth(token);
  if (supabaseAuth) {
    runWithDbAuthContext(supabaseAuth, () => {
      applyAuthContext(res, supabaseAuth);
      next();
    });
    return;
  }

  if (config.authMode !== 'dev' && !hasSupabaseVerifierConfig()) {
    next(
      new ApiError(
        500,
        'AUTH_CONFIG_ERROR',
        'Supabase auth is enabled but no verifier is configured. Set SUPABASE_JWT_SECRET or SUPABASE_JWKS_URL.'
      )
    );
    return;
  }

  if (config.authDebugErrors) {
    next(new ApiError(401, 'UNAUTHORIZED', `Invalid token (${compactTokenDebugSummary(token)})`));
    return;
  }

  next(new ApiError(401, 'UNAUTHORIZED', 'Invalid token'));
}
