import dotenv from 'dotenv';

dotenv.config({ override: process.env.NODE_ENV !== 'test' });

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function numberWithDefault(name: string, defaultValue: number): number {
  const raw = process.env[name];
  if (!raw) {
    return defaultValue;
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : defaultValue;
}

function integerWithDefault(name: string, defaultValue: number): number {
  const parsed = Math.floor(numberWithDefault(name, defaultValue));
  return Number.isFinite(parsed) ? parsed : defaultValue;
}

function booleanWithDefault(name: string, defaultValue: boolean): boolean {
  const raw = process.env[name];
  if (!raw) {
    return defaultValue;
  }
  const normalized = raw.trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(normalized)) {
    return true;
  }
  if (['0', 'false', 'no', 'off'].includes(normalized)) {
    return false;
  }
  return defaultValue;
}

function csvListWithDefault(name: string, defaultValue: string[]): string[] {
  const raw = (process.env[name] || '').trim();
  if (!raw) {
    return defaultValue.map((entry) => entry.trim().toLowerCase()).filter(Boolean);
  }
  return raw
    .split(',')
    .map((entry) => entry.trim().toLowerCase())
    .filter(Boolean);
}

type AuthMode = 'dev' | 'supabase' | 'hybrid';

function authModeWithDefault(name: string, defaultValue: AuthMode): AuthMode {
  const raw = (process.env[name] || '').trim().toLowerCase();
  if (raw === 'dev' || raw === 'supabase' || raw === 'hybrid') {
    return raw;
  }
  return defaultValue;
}

export const config = {
  port: Number(process.env.PORT || 8080),
  databaseUrl: required('DATABASE_URL'),
  databaseSsl: booleanWithDefault('DATABASE_SSL', false),
  rlsStrictMode: booleanWithDefault('RLS_STRICT_MODE', false),
  authMode: authModeWithDefault('AUTH_MODE', 'dev'),
  authBearerDevPrefix: process.env.AUTH_BEARER_DEV_PREFIX || 'dev-',
  authDebugErrors: booleanWithDefault('AUTH_DEBUG_ERRORS', false),
  supabaseJwtSecret: process.env.SUPABASE_JWT_SECRET || '',
  supabaseJwtIssuer: process.env.SUPABASE_JWT_ISSUER || '',
  supabaseJwksUrl: process.env.SUPABASE_JWKS_URL || '',
  supabaseJwtAudience: process.env.SUPABASE_JWT_AUDIENCE || 'authenticated',
  supabaseJwtClockSkewSeconds: integerWithDefault('SUPABASE_JWT_CLOCK_SKEW_SECONDS', 30),
  adminEmails: csvListWithDefault('ADMIN_EMAILS', ['shantanuodak@yahoo.com', 'shantanuodak1993@gmail.com']),
  geminiApiKey: process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY || '',
  geminiApiBaseUrl: process.env.GEMINI_API_BASE_URL || 'https://generativelanguage.googleapis.com/v1beta',
  geminiFlashModel: process.env.GEMINI_FLASH_MODEL || 'gemini-2.5-flash',
  geminiFlashLiteModel: process.env.GEMINI_FLASH_LITE_MODEL || 'gemini-2.5-flash-lite',
  geminiTimeoutMs: integerWithDefault('GEMINI_TIMEOUT_MS', 20_000),
  usdaApiKey: process.env.USDA_API_KEY || '',
  usdaApiBaseUrl: process.env.USDA_API_BASE_URL || 'https://api.nal.usda.gov/fdc/v1',
  usdaTimeoutMs: integerWithDefault('USDA_TIMEOUT_MS', 8_000),
  fatSecretClientId: process.env.FATSECRET_CLIENT_ID || process.env.FAT_SECRET_CLIENT_ID || '',
  fatSecretClientSecret: process.env.FATSECRET_CLIENT_SECRET || process.env.FAT_SECRET_CLIENT_SECRET || '',
  fatSecretScope: process.env.FATSECRET_SCOPE || process.env.FAT_SECRET_SCOPE || 'premier',
  fatSecretTokenUrl: process.env.FATSECRET_TOKEN_URL || 'https://oauth.fatsecret.com/connect/token',
  fatSecretApiBaseUrl: process.env.FATSECRET_API_BASE_URL || 'https://platform.fatsecret.com/rest',
  fatSecretTimeoutMs: integerWithDefault('FATSECRET_TIMEOUT_MS', 8_000),
  geminiAbortRetryCount: integerWithDefault('GEMINI_ABORT_RETRY_COUNT', 0),
  geminiRetryMaxAttempts: integerWithDefault('GEMINI_RETRY_MAX_ATTEMPTS', 1),
  geminiRetryBaseDelayMs: integerWithDefault('GEMINI_RETRY_BASE_DELAY_MS', 500),
  geminiRetryMaxDelayMs: integerWithDefault('GEMINI_RETRY_MAX_DELAY_MS', 4_000),
  geminiRetryJitterMs: integerWithDefault('GEMINI_RETRY_JITTER_MS', 200),
  parseRateLimitEnabled: booleanWithDefault('PARSE_RATE_LIMIT_ENABLED', true),
  parseRateLimitWindowMs: integerWithDefault('PARSE_RATE_LIMIT_WINDOW_MS', 60_000),
  parseRateLimitMaxRequests: integerWithDefault('PARSE_RATE_LIMIT_MAX_REQUESTS', 60),
  geminiCircuitBreakerEnabled: booleanWithDefault('GEMINI_CIRCUIT_BREAKER_ENABLED', true),
  geminiCircuitBreakerConsecutive429: integerWithDefault('GEMINI_CIRCUIT_BREAKER_CONSECUTIVE_429', 5),
  geminiCircuitBreakerCooldownMs: integerWithDefault('GEMINI_CIRCUIT_BREAKER_COOLDOWN_MS', 20_000),
  debugParseCacheKey: process.env.DEBUG_PARSE_CACHE_KEY === 'true',
  aiFallbackEnabled: process.env.AI_FALLBACK_ENABLED !== 'false',
  aiFallbackConfidenceMin: numberWithDefault('AI_FALLBACK_CONFIDENCE_MIN', 0.5),
  aiFallbackConfidenceMax: numberWithDefault('AI_FALLBACK_CONFIDENCE_MAX', 0.85),
  parseCacheMinConfidence: numberWithDefault('PARSE_CACHE_MIN_CONFIDENCE', 0.7),
  aiFallbackModelName: process.env.AI_FALLBACK_MODEL_NAME || process.env.GEMINI_FLASH_MODEL || 'gemini-2.5-flash',
  aiFallbackCostUsd: numberWithDefault('AI_FALLBACK_COST_USD', 0.0008),
  aiImageParseEnabled: booleanWithDefault('AI_IMAGE_PARSE_ENABLED', true),
  aiImagePrimaryModel: process.env.AI_IMAGE_PRIMARY_MODEL || process.env.GEMINI_FLASH_MODEL || 'gemini-2.5-flash',
  aiImageFallbackModel: process.env.AI_IMAGE_FALLBACK_MODEL || process.env.GEMINI_FLASH_MODEL || 'gemini-2.5-flash',
  aiImageEnableFallback: booleanWithDefault('AI_IMAGE_ENABLE_FALLBACK', true),
  aiImageConfidenceMin: numberWithDefault('AI_IMAGE_CONFIDENCE_MIN', 0.7),
  aiImageMaxBytes: integerWithDefault('AI_IMAGE_MAX_BYTES', 6_291_456),
  geminiFlashLiteInputUsdPer1M: numberWithDefault('GEMINI_FLASH_LITE_INPUT_USD_PER_1M', 0.10),
  geminiFlashLiteOutputUsdPer1M: numberWithDefault('GEMINI_FLASH_LITE_OUTPUT_USD_PER_1M', 0.40),
  geminiFlashInputUsdPer1M: numberWithDefault('GEMINI_FLASH_INPUT_USD_PER_1M', 0.30),
  geminiFlashOutputUsdPer1M: numberWithDefault('GEMINI_FLASH_OUTPUT_USD_PER_1M', 2.50),
  aiEscalationEnabled: process.env.AI_ESCALATION_ENABLED === 'true',
  aiEscalationModelName: process.env.AI_ESCALATION_MODEL_NAME || process.env.GEMINI_FLASH_MODEL || 'gemini-2.5-flash',
  aiEscalationCostUsd: numberWithDefault('AI_ESCALATION_COST_USD', 0.003),
  aiDailyBudgetUsd: numberWithDefault('AI_DAILY_BUDGET_USD', 0.5),
  aiUserSoftCapUsd: numberWithDefault('AI_USER_SOFT_CAP_USD', 0.1),
  internalMetricsKey: process.env.INTERNAL_METRICS_KEY || '',
  parseCacheSchemaVersion: process.env.PARSE_CACHE_SCHEMA_VERSION || 'k4',
  parseVersion: process.env.PARSE_VERSION || 'v2',
  parseProviderRouteVersion: process.env.PARSE_PROVIDER_ROUTE_VERSION || 'r2',
  parsePromptVersion:
    process.env.PARSE_PROMPT_VERSION ||
    `${process.env.AI_FALLBACK_MODEL_NAME || process.env.GEMINI_FLASH_MODEL || 'gemini-2.5-flash'}:v2`,
  parseRequestTtlHours: numberWithDefault('PARSE_REQUEST_TTL_HOURS', 24),
  alertEscalationRateThreshold: numberWithDefault('ALERT_ESCALATION_RATE_THRESHOLD', 0.08),
  alertEscalationWindowMinutes: numberWithDefault('ALERT_ESCALATION_WINDOW_MINUTES', 15),
  alertCacheHitRatioThreshold: numberWithDefault('ALERT_CACHE_HIT_RATIO_THRESHOLD', 0.3),
  alertCacheWindowHours: numberWithDefault('ALERT_CACHE_WINDOW_HOURS', 24),
  alertCostPerLogTargetUsd: numberWithDefault('ALERT_COST_PER_LOG_TARGET_USD', 0.001),
  alertCostPerLogDriftThreshold: numberWithDefault('ALERT_COST_PER_LOG_DRIFT_THRESHOLD', 0.2),
  alertCostWindowHours: numberWithDefault('ALERT_COST_WINDOW_HOURS', 24),
  alertMinParseRequests: numberWithDefault('ALERT_MIN_PARSE_REQUESTS', 20),
  alertMinLogs: numberWithDefault('ALERT_MIN_LOGS', 20),
  progressFeatureEnabled: booleanWithDefault('PROGRESS_FEATURE_ENABLED', true)
};
