import { afterAll, beforeAll, beforeEach, describe, expect, test } from 'vitest';
import request from 'supertest';
import { Pool } from 'pg';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Express } from 'express';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const TEST_DB_URL = process.env.DATABASE_URL_TEST;
const shouldRunIntegration = process.env.RUN_INTEGRATION_TESTS === 'true';
const hasTestDb = shouldRunIntegration && Boolean(TEST_DB_URL);

describe.skipIf(!hasTestDb)('Integration API flow', () => {
  const userId = '11111111-1111-1111-1111-111111111111';
  const authHeader = { Authorization: `Bearer dev-${userId}` };
  const expectedParseVersion = process.env.PARSE_VERSION || 'v2';

  let pool: Pool;
  let app: Express;
  let originalFetch: typeof globalThis.fetch | undefined;

  function buildGeminiResultFromMealText(mealText: string): Record<string, unknown> {
    const normalized = mealText.trim().toLowerCase();

    if (normalized.includes('mystery blob')) {
      return {
        confidence: 0.25,
        assumptions: ['Ambiguous food phrase; using a conservative estimate.'],
        items: [
          {
            name: 'mystery cafe item',
            quantity: 1,
            amount: 1,
            unit: 'serving',
            unitNormalized: 'serving',
            grams: 120,
            gramsPerUnit: 120,
            calories: 180,
            protein: 5,
            carbs: 20,
            fat: 8,
            matchConfidence: 0.3,
            nutritionSourceId: 'gemini_mystery_serving',
            sourceFamily: 'gemini',
            originalNutritionSourceId: 'gemini_mystery_serving',
            needsClarification: true,
            manualOverride: false,
            foodDescription: 'A generic cafe-style mixed dish.',
            explanation: 'The text does not map to a specific known food. I used a single serving estimate for a mixed cafe item. Calories and macros are conservative placeholders. Please clarify the exact food for better accuracy.'
          }
        ],
        totals: { calories: 180, protein: 5, carbs: 20, fat: 8 }
      };
    }

    if (normalized.includes('egs') || normalized.includes('eggs') || normalized.includes('toast')) {
      const quantity = normalized.includes('3 egs') ? 3 : 2;
      const eggCalories = quantity * 72;
      const toastCalories = 80;
      return {
        confidence: 0.82,
        assumptions: ['Interpreted "egs" as eggs and toast as one slice.'],
        items: [
          {
            name: 'egg',
            quantity,
            amount: quantity,
            unit: 'count',
            unitNormalized: 'count',
            grams: quantity * 50,
            gramsPerUnit: 50,
            calories: eggCalories,
            protein: +(quantity * 6.3).toFixed(1),
            carbs: +(quantity * 0.6).toFixed(1),
            fat: +(quantity * 4.8).toFixed(1),
            matchConfidence: 0.9,
            nutritionSourceId: 'gemini_egg_count',
            sourceFamily: 'gemini',
            originalNutritionSourceId: 'gemini_egg_count',
            needsClarification: false,
            manualOverride: false,
            foodDescription: 'Whole eggs, common serving size by count.',
            explanation: 'I interpreted "egs" as eggs. I used standard nutrition values for large eggs per count. The quantity was scaled from the text. Totals reflect only the egg portion here.'
          },
          {
            name: 'toast',
            quantity: 1,
            amount: 1,
            unit: 'slice',
            unitNormalized: 'slice',
            grams: 30,
            gramsPerUnit: 30,
            calories: toastCalories,
            protein: 3,
            carbs: 14,
            fat: 1,
            matchConfidence: 0.85,
            nutritionSourceId: 'gemini_toast_slice',
            sourceFamily: 'gemini',
            originalNutritionSourceId: 'gemini_toast_slice',
            needsClarification: false,
            manualOverride: false,
            foodDescription: 'One toasted bread slice.',
            explanation: 'I mapped toast to one standard bread slice. A slice baseline was used for grams and macros. This keeps the estimate practical for logging. Adjust quantity later if needed.'
          }
        ],
        totals: {
          calories: eggCalories + toastCalories,
          protein: +(quantity * 6.3 + 3).toFixed(1),
          carbs: +(quantity * 0.6 + 14).toFixed(1),
          fat: +(quantity * 4.8 + 1).toFixed(1)
        }
      };
    }

    return {
      confidence: 0.86,
      assumptions: ['Used practical serving estimates for listed foods.'],
      items: [
        {
          name: 'mixed meal entry',
          quantity: 1,
          amount: 1,
          unit: 'serving',
          unitNormalized: 'serving',
          grams: 300,
          gramsPerUnit: 300,
          calories: 306,
          protein: 18.9,
          carbs: 29.2,
          fat: 11.6,
          matchConfidence: 0.88,
          nutritionSourceId: 'gemini_mixed_serving',
          sourceFamily: 'gemini',
          originalNutritionSourceId: 'gemini_mixed_serving',
          needsClarification: false,
          manualOverride: false,
          foodDescription: 'A mixed meal parsed from user-entered text.',
          explanation: 'I converted the entered foods into one practical serving estimate. Macros were balanced to match a typical mixed meal profile. Totals are rounded for stable logging. You can refine item-level details in edit mode.'
        }
      ],
      totals: { calories: 306, protein: 18.9, carbs: 29.2, fat: 11.6 }
    };
  }

  function extractMealTextFromPrompt(prompt: string): string {
    const match = prompt.match(/User meal text:\s*([^\n]+)/i);
    if (match?.[1]) {
      return match[1].trim();
    }
    return 'meal';
  }

  beforeAll(async () => {
    process.env.NODE_ENV = 'test';
    process.env.DATABASE_URL = TEST_DB_URL;
    process.env.AI_ESCALATION_ENABLED = 'true';
    process.env.AI_DAILY_BUDGET_USD = '0.001';
    process.env.AI_USER_SOFT_CAP_USD = '0.0005';
    process.env.AI_FALLBACK_COST_USD = '0.0008';
    process.env.AI_ESCALATION_COST_USD = '0.0002';
    process.env.INTERNAL_METRICS_KEY = 'metrics-test-key';
    process.env.ALERT_MIN_PARSE_REQUESTS = '1';
    process.env.ALERT_MIN_LOGS = '1';
    process.env.ALERT_COST_PER_LOG_TARGET_USD = '0.0001';
    process.env.AUTH_MODE = 'dev';
    process.env.DEBUG_PARSE_CACHE_KEY = 'true';
    process.env.GEMINI_API_KEY = 'test-gemini-key';
    process.env.PARSE_RATE_LIMIT_ENABLED = 'false';
    process.env.PARSE_RATE_LIMIT_MAX_REQUESTS = '100';

    originalFetch = globalThis.fetch;
    globalThis.fetch = (async (_input: RequestInfo | URL, init?: RequestInit) => {
      const body = typeof init?.body === 'string' ? init.body : '';
      let prompt = '';
      try {
        const parsed = JSON.parse(body) as { contents?: Array<{ parts?: Array<{ text?: string }> }> };
        prompt = parsed.contents?.[0]?.parts?.[0]?.text || '';
      } catch {
        prompt = '';
      }

      const mealText = extractMealTextFromPrompt(prompt);
      const parsePayload = buildGeminiResultFromMealText(mealText);
      const payload = {
        candidates: [{ content: { parts: [{ text: JSON.stringify(parsePayload) }] } }],
        usageMetadata: {
          promptTokenCount: 120,
          candidatesTokenCount: 180,
          totalTokenCount: 300
        }
      };

      return {
        ok: true,
        status: 200,
        json: async () => payload,
        text: async () => JSON.stringify(payload)
      } as Response;
    }) as typeof globalThis.fetch;

    pool = new Pool({ connectionString: TEST_DB_URL });

    const { runMigrations } = await import('../src/db/migrations.js');
    const migrationsDir = path.resolve(__dirname, '../migrations');
    await runMigrations(pool, migrationsDir);

    const appModule = await import('../src/app.js');
    app = appModule.createApp();
  });

  beforeEach(async () => {
    await pool.query(
      'TRUNCATE TABLE food_log_items, food_logs, onboarding_profiles, users, admin_feature_flags, parse_cache, parse_requests, log_save_idempotency, ai_cost_events RESTART IDENTITY CASCADE'
    );

    await pool.query(
      `
      INSERT INTO users (id, email, auth_provider, is_admin)
      VALUES ($1, $2, 'dev', false)
      ON CONFLICT (id) DO NOTHING
      `,
      [userId, `${userId}@dev.local`]
    );

    await pool.query(
      `
      INSERT INTO admin_feature_flags (user_id, gemini_enabled, fatsecret_enabled)
      VALUES ($1, true, false)
      ON CONFLICT (user_id) DO UPDATE
      SET gemini_enabled = EXCLUDED.gemini_enabled,
          updated_at = NOW()
      `,
      [userId]
    );
  });

  afterAll(async () => {
    if (originalFetch) {
      globalThis.fetch = originalFetch;
    }
    await pool.end();
  });

  test('onboarding -> parse -> save -> day-summary flow', async () => {
    const onboardingPayload = {
      goal: 'maintain',
      dietPreference: 'none',
      allergies: [],
      units: 'imperial',
      activityLevel: 'moderate',
      timezone: 'America/New_York',
      age: 30,
      sex: 'male',
      heightCm: 170,
      weightKg: 70,
      pace: 'balanced',
      activityDetail: 'lightlyActive'
    };

    const onboardingResponse = await request(app)
      .post('/v1/onboarding')
      .set(authHeader)
      .send(onboardingPayload);

    expect(onboardingResponse.status).toBe(200);
    expect(onboardingResponse.body.calorieTarget).toBeGreaterThan(0);

    const profileResponse = await request(app)
      .get('/v1/onboarding')
      .set(authHeader);

    expect(profileResponse.status).toBe(200);
    expect(profileResponse.body.goal).toBe(onboardingPayload.goal);
    expect(profileResponse.body.units).toBe(onboardingPayload.units);
    expect(profileResponse.body.activityLevel).toBe(onboardingPayload.activityLevel);
    expect(profileResponse.body.timezone).toBe(onboardingPayload.timezone);
    expect(profileResponse.body.age).toBe(onboardingPayload.age);
    expect(profileResponse.body.sex).toBe(onboardingPayload.sex);
    expect(profileResponse.body.heightCm).toBe(onboardingPayload.heightCm);
    expect(profileResponse.body.weightKg).toBe(onboardingPayload.weightKg);
    expect(profileResponse.body.pace).toBe(onboardingPayload.pace);
    expect(profileResponse.body.activityDetail).toBe(onboardingPayload.activityDetail);
    expect(profileResponse.body.calorieTarget).toBe(onboardingResponse.body.calorieTarget);
    expect(profileResponse.body.macroTargets).toEqual(onboardingResponse.body.macroTargets);

    const parseResponse = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '2 eggs, 2 slices toast, black coffee',
        loggedAt: '2026-02-15T13:35:00.000Z'
      });

    expect(parseResponse.status).toBe(200);
    expect(['cache', 'gemini', 'unresolved']).toContain(parseResponse.body.route);
    expect(parseResponse.body.cacheHit).toBe(false);
    expect(parseResponse.body.parseRequestId).toBeTruthy();
    expect(parseResponse.body.parseVersion).toBe(expectedParseVersion);
    expect(Array.isArray(parseResponse.body.sourcesUsed)).toBe(true);
    expect(parseResponse.body.items.length).toBeGreaterThan(0);
    expect(typeof parseResponse.body.items[0].amount).toBe('number');
    expect(typeof parseResponse.body.items[0].unitNormalized).toBe('string');
    expect('gramsPerUnit' in parseResponse.body.items[0]).toBe(true);
    expect(typeof parseResponse.body.items[0].needsClarification).toBe('boolean');
    expect(typeof parseResponse.body.items[0].manualOverride).toBe('boolean');

    const parseResponseCached = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '2 eggs, 2 slices toast, black coffee',
        loggedAt: '2026-02-15T13:35:00.000Z'
      });

    expect(parseResponseCached.status).toBe(200);
    expect(parseResponseCached.body.cacheHit).toBe(true);

    const saveResponse = await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', '8f0a8477-45f3-4fc5-a0be-6de1deed18ad')
      .send({
        parseRequestId: parseResponse.body.parseRequestId,
        parseVersion: parseResponse.body.parseVersion,
        parsedLog: {
          rawText: '2 eggs, 2 slices toast, black coffee',
          loggedAt: '2026-02-15T13:35:00.000Z',
          inputKind: 'image',
          imageRef: 'users/test-user/food-logs/2026/02/photo.jpg',
          confidence: parseResponse.body.confidence,
          totals: parseResponse.body.totals,
          items: parseResponse.body.items
        }
      });

    expect(saveResponse.status).toBe(200);
    expect(saveResponse.body.status).toBe('saved');
    expect(saveResponse.body.logId).toBeTruthy();
    expect(saveResponse.body.healthSync?.syncMode).toBe('per-log');
    expect(saveResponse.body.healthSync?.action).toBe('upsert');
    expect(typeof saveResponse.body.healthSync?.healthWriteKey).toBe('string');
    expect(saveResponse.body.healthSync?.healthWriteKey?.length).toBeGreaterThan(10);

    const dayLogsResponse = await request(app)
      .get('/v1/logs/day-logs')
      .set(authHeader)
      .query({ date: '2026-02-15' });

    expect(dayLogsResponse.status).toBe(200);
    expect(dayLogsResponse.body.logs[0].inputKind).toBe('image');
    expect(dayLogsResponse.body.logs[0].imageRef).toBe('users/test-user/food-logs/2026/02/photo.jpg');

    const summaryResponse = await request(app)
      .get('/v1/logs/day-summary')
      .set(authHeader)
      .query({ date: '2026-02-15' });

    expect(summaryResponse.status).toBe(200);
    expect(summaryResponse.body.date).toBe('2026-02-15');
    expect(summaryResponse.body.totals.calories).toBeGreaterThan(0);
    expect(summaryResponse.body.targets.calories).toBe(onboardingResponse.body.calorieTarget);
    expect(summaryResponse.body.targets.protein).toBe(onboardingResponse.body.macroTargets.protein);
    expect(summaryResponse.body.targets.carbs).toBe(onboardingResponse.body.macroTargets.carbs);
    expect(summaryResponse.body.targets.fat).toBe(onboardingResponse.body.macroTargets.fat);
    expect(typeof summaryResponse.body.remaining.calories).toBe('number');
  });

  test('delete log removes log/items, refreshes day data, and preserves parse cache', async () => {
    const onboarding = await request(app)
      .post('/v1/onboarding')
      .set(authHeader)
      .send({
        goal: 'maintain',
        dietPreference: 'none',
        allergies: [],
        units: 'imperial',
        activityLevel: 'moderate',
        timezone: 'America/New_York',
        age: 30,
        sex: 'male',
        heightCm: 170,
        weightKg: 70,
        pace: 'balanced',
        activityDetail: 'lightlyActive'
      });
    expect(onboarding.status).toBe(200);

    const parseResponse = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '2 eggs and toast',
        loggedAt: '2026-02-15T13:35:00.000Z'
      });
    expect(parseResponse.status).toBe(200);

    const parseResponseCached = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '2 eggs and toast',
        loggedAt: '2026-02-15T13:35:00.000Z'
      });
    expect(parseResponseCached.status).toBe(200);
    expect(parseResponseCached.body.cacheHit).toBe(true);

    const saveResponse = await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', '066a85b1-9759-4e9f-a724-6af999da3a4b')
      .send({
        parseRequestId: parseResponse.body.parseRequestId,
        parseVersion: parseResponse.body.parseVersion,
        parsedLog: {
          rawText: '2 eggs and toast',
          loggedAt: '2026-02-15T13:35:00.000Z',
          confidence: parseResponse.body.confidence,
          totals: parseResponse.body.totals,
          items: parseResponse.body.items
        }
      });
    expect(saveResponse.status).toBe(200);

    const logId = saveResponse.body.logId;
    const itemRowsBefore = await pool.query<{ c: string }>(
      'SELECT COUNT(*)::text AS c FROM food_log_items WHERE food_log_id = $1',
      [logId]
    );
    expect(Number(itemRowsBefore.rows[0].c)).toBeGreaterThan(0);

    const otherUserDelete = await request(app)
      .delete(`/v1/logs/${logId}`)
      .set({ Authorization: 'Bearer dev-22222222-2222-2222-2222-222222222222' });
    expect(otherUserDelete.status).toBe(404);
    expect(otherUserDelete.body.error.code).toBe('LOG_NOT_FOUND');

    const cacheBeforeDelete = await pool.query<{ c: string }>('SELECT COUNT(*)::text AS c FROM parse_cache');
    expect(Number(cacheBeforeDelete.rows[0].c)).toBeGreaterThan(0);

    const deleteResponse = await request(app)
      .delete(`/v1/logs/${logId}`)
      .set(authHeader);
    expect(deleteResponse.status).toBe(200);
    expect(deleteResponse.body.status).toBe('deleted');
    expect(deleteResponse.body.logId).toBe(logId);
    expect(deleteResponse.body.healthSync?.action).toBe('delete');

    const logRowsAfter = await pool.query<{ c: string }>(
      'SELECT COUNT(*)::text AS c FROM food_logs WHERE id = $1',
      [logId]
    );
    expect(Number(logRowsAfter.rows[0].c)).toBe(0);

    const itemRowsAfter = await pool.query<{ c: string }>(
      'SELECT COUNT(*)::text AS c FROM food_log_items WHERE food_log_id = $1',
      [logId]
    );
    expect(Number(itemRowsAfter.rows[0].c)).toBe(0);

    const summaryAfterDelete = await request(app)
      .get('/v1/logs/day-summary')
      .set(authHeader)
      .query({ date: '2026-02-15' });
    expect(summaryAfterDelete.status).toBe(200);
    expect(summaryAfterDelete.body.totals.calories).toBe(0);

    const logsAfterDelete = await request(app)
      .get('/v1/logs/day-logs')
      .set(authHeader)
      .query({ date: '2026-02-15' });
    expect(logsAfterDelete.status).toBe(200);
    expect(logsAfterDelete.body.logs).toEqual([]);

    const cacheAfterDelete = await pool.query<{ c: string }>('SELECT COUNT(*)::text AS c FROM parse_cache');
    expect(Number(cacheAfterDelete.rows[0].c)).toBe(Number(cacheBeforeDelete.rows[0].c));
  });

  test('onboarding provenance is persisted and reproducible for identical inputs', async () => {
    const payload = {
      goal: 'maintain',
      dietPreference: 'none',
      allergies: ['peanut'],
      units: 'metric',
      activityLevel: 'moderate',
      age: 25,
      sex: 'female',
      heightCm: 160,
      weightKg: 55,
      pace: 'conservative',
      activityDetail: 'moderatelyActive',
      timezone: 'America/New_York'
    };

    const first = await request(app).post('/v1/onboarding').set(authHeader).send(payload);
    expect(first.status).toBe(200);

    const firstProv = await request(app).get('/v1/onboarding/provenance').set(authHeader);
    expect(firstProv.status).toBe(200);
    expect(firstProv.body.mode).toBe('computed_provenance_v1');
    expect(firstProv.body.calculatorVersion).toBe('onboarding-target-calculator-v3');
    expect(typeof firstProv.body.inputsHash).toBe('string');
    expect(firstProv.body.inputsHash.length).toBe(64);
    expect(firstProv.body.inputs.timezone).toBe('America/New_York');
    expect(firstProv.body.inputs.units).toBe('metric');
    expect(firstProv.body.inputs.age).toBe(25);
    expect(firstProv.body.inputs.sex).toBe('female');
    expect(firstProv.body.inputs.heightCm).toBe(160);
    expect(firstProv.body.inputs.weightKg).toBe(55);
    expect(firstProv.body.inputs.pace).toBe('conservative');
    expect(firstProv.body.inputs.activityDetail).toBe('moderatelyActive');

    const second = await request(app).post('/v1/onboarding').set(authHeader).send(payload);
    expect(second.status).toBe(200);

    const secondProv = await request(app).get('/v1/onboarding/provenance').set(authHeader);
    expect(secondProv.status).toBe(200);
    expect(secondProv.body.mode).toBe('computed_provenance_v1');
    expect(secondProv.body.calculatorVersion).toBe('onboarding-target-calculator-v3');
    expect(secondProv.body.inputsHash).toBe(firstProv.body.inputsHash);
    expect(secondProv.body.inputs).toEqual(firstProv.body.inputs);
  });

  test('legacy onboarding request without biometric fields still succeeds', async () => {
    const response = await request(app)
      .post('/v1/onboarding')
      .set(authHeader)
      .send({
        goal: 'maintain',
        dietPreference: 'none',
        allergies: [],
        units: 'imperial',
        activityLevel: 'moderate',
        timezone: 'UTC'
      });

    expect(response.status).toBe(200);
    expect(response.body.calorieTarget).toBe(2200);
    expect(response.body.macroTargets.protein).toBeGreaterThan(0);

    const provenance = await request(app).get('/v1/onboarding/provenance').set(authHeader);
    expect(provenance.status).toBe(200);
    expect(provenance.body.calculatorVersion).toBe('onboarding-target-calculator-v3');
    expect(provenance.body.inputs.age).toBeNull();
    expect(provenance.body.inputs.sex).toBeNull();
    expect(provenance.body.inputs.heightCm).toBeNull();
    expect(provenance.body.inputs.weightKg).toBeNull();
  });

  test('cache key namespace changes when onboarding units change', async () => {
    const onboardingMetric = await request(app)
      .post('/v1/onboarding')
      .set(authHeader)
      .send({
        goal: 'maintain',
        dietPreference: 'none',
        allergies: [],
        units: 'metric',
        activityLevel: 'moderate',
        timezone: 'UTC'
      });

    expect(onboardingMetric.status).toBe(200);

    const first = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .set('Accept-Language', 'en-US')
      .send({
        text: 'cache key namespace meal',
        loggedAt: '2026-02-15T13:35:00.000Z'
      });

    expect(first.status).toBe(200);
    expect(first.body.cacheHit).toBe(false);
    expect(typeof first.body.cacheDebug?.textHash).toBe('string');
    expect(first.body.cacheDebug.scope).toContain('units=metric');
    expect(first.body.cacheDebug.scope).toContain('locale=en-us');

    const second = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .set('Accept-Language', 'en-US')
      .send({
        text: 'cache key namespace meal',
        loggedAt: '2026-02-15T13:35:00.000Z'
      });

    expect(second.status).toBe(200);
    expect(second.body.cacheHit).toBe(true);
    expect(second.body.cacheDebug.textHash).toBe(first.body.cacheDebug.textHash);

    const onboardingImperial = await request(app)
      .post('/v1/onboarding')
      .set(authHeader)
      .send({
        goal: 'maintain',
        dietPreference: 'none',
        allergies: [],
        units: 'imperial',
        activityLevel: 'moderate',
        timezone: 'UTC'
      });

    expect(onboardingImperial.status).toBe(200);

    const third = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .set('Accept-Language', 'en-US')
      .send({
        text: 'cache key namespace meal',
        loggedAt: '2026-02-15T13:35:00.000Z'
      });

    expect(third.status).toBe(200);
    expect(third.body.cacheHit).toBe(false);
    expect(third.body.cacheDebug.scope).toContain('units=imperial');
    expect(third.body.cacheDebug.textHash).not.toBe(first.body.cacheDebug.textHash);
  });

  test('day-summary is user-scoped', async () => {
    const otherUserId = '22222222-2222-2222-2222-222222222222';

    await request(app)
      .post('/v1/onboarding')
      .set({ Authorization: `Bearer dev-${otherUserId}` })
      .send({
        goal: 'maintain',
        dietPreference: 'none',
        allergies: [],
        units: 'imperial',
        activityLevel: 'moderate'
      });

    const parse = await request(app)
      .post('/v1/logs/parse')
      .set({ Authorization: `Bearer dev-${otherUserId}` })
      .send({
        text: '1 egg',
        loggedAt: '2026-02-15T09:00:00.000Z'
      });

    await request(app)
      .post('/v1/logs')
      .set({ Authorization: `Bearer dev-${otherUserId}` })
      .set('Idempotency-Key', 'a57f00f5-8fb4-4d72-b1fd-98f7f53e83ca')
      .send({
        parseRequestId: parse.body.parseRequestId,
        parseVersion: parse.body.parseVersion,
        parsedLog: {
          rawText: '1 egg',
          loggedAt: '2026-02-15T09:00:00.000Z',
          confidence: parse.body.confidence,
          totals: parse.body.totals,
          items: parse.body.items
        }
      });

    await request(app)
      .post('/v1/onboarding')
      .set(authHeader)
      .send({
        goal: 'maintain',
        dietPreference: 'none',
        allergies: [],
        units: 'imperial',
        activityLevel: 'moderate'
      });

    const summary = await request(app)
      .get('/v1/logs/day-summary')
      .set(authHeader)
      .query({ date: '2026-02-15' });

    expect(summary.status).toBe(200);
    expect(summary.body.totals.calories).toBe(0);
  });

  test('day-summary uses onboarding timezone by default and supports tz override', async () => {
    const onboarding = await request(app)
      .post('/v1/onboarding')
      .set(authHeader)
      .send({
        goal: 'maintain',
        dietPreference: 'none',
        allergies: [],
        units: 'imperial',
        activityLevel: 'moderate',
        timezone: 'America/Los_Angeles'
      });

    expect(onboarding.status).toBe(200);

    const parse = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '1 egg',
        loggedAt: '2026-02-16T07:30:00.000Z'
      });

    expect(parse.status).toBe(200);

    const save = await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', 'f8f34c98-6b79-49f6-a6ec-3286807654ef')
      .send({
        parseRequestId: parse.body.parseRequestId,
        parseVersion: parse.body.parseVersion,
        parsedLog: {
          rawText: '1 egg',
          loggedAt: '2026-02-16T07:30:00.000Z',
          confidence: parse.body.confidence,
          totals: parse.body.totals,
          items: parse.body.items
        }
      });

    expect(save.status).toBe(200);

    const summaryProfileTz = await request(app)
      .get('/v1/logs/day-summary')
      .set(authHeader)
      .query({ date: '2026-02-15' });

    expect(summaryProfileTz.status).toBe(200);
    expect(summaryProfileTz.body.timezone).toBe('America/Los_Angeles');
    expect(summaryProfileTz.body.totals.calories).toBeGreaterThan(0);

    const summaryUtcOverride = await request(app)
      .get('/v1/logs/day-summary')
      .set(authHeader)
      .query({ date: '2026-02-16', tz: 'UTC' });

    expect(summaryUtcOverride.status).toBe(200);
    expect(summaryUtcOverride.body.timezone).toBe('UTC');
    expect(summaryUtcOverride.body.totals.calories).toBeGreaterThan(0);
  });

  test('progress endpoint returns date-range rows with streak and weekly delta', async () => {
    const onboarding = await request(app)
      .post('/v1/onboarding')
      .set(authHeader)
      .send({
        goal: 'maintain',
        dietPreference: 'none',
        allergies: [],
        units: 'imperial',
        activityLevel: 'moderate',
        timezone: 'America/Los_Angeles'
      });

    expect(onboarding.status).toBe(200);

    const saveForDate = async (dateIso: string, idempotencyKey: string) => {
      const parse = await request(app)
        .post('/v1/logs/parse')
        .set(authHeader)
        .send({
          text: '2 eggs, toast',
          loggedAt: dateIso
        });

      expect(parse.status).toBe(200);

      const save = await request(app)
        .post('/v1/logs')
        .set(authHeader)
        .set('Idempotency-Key', idempotencyKey)
        .send({
          parseRequestId: parse.body.parseRequestId,
          parseVersion: parse.body.parseVersion,
          parsedLog: {
            rawText: '2 eggs, toast',
            loggedAt: dateIso,
            confidence: parse.body.confidence,
            totals: parse.body.totals,
            items: parse.body.items
          }
        });

      expect(save.status).toBe(200);
    };

    await saveForDate('2026-02-18T13:00:00.000Z', 'e8c0ab02-f7c7-4f43-8f3a-2f5bc9185d2a');
    await saveForDate('2026-02-20T13:00:00.000Z', '317f8f29-c32c-4f0f-b65e-c7128dd733f8');
    await saveForDate('2026-02-21T13:00:00.000Z', 'd665ddaa-2a84-4ef7-b6cf-f9fe84ab7ca7');

    const progress = await request(app)
      .get('/v1/logs/progress')
      .set(authHeader)
      .query({
        from: '2026-02-17',
        to: '2026-02-21'
      });

    expect(progress.status).toBe(200);
    expect(progress.body.from).toBe('2026-02-17');
    expect(progress.body.to).toBe('2026-02-21');
    expect(progress.body.timezone).toBe('America/Los_Angeles');
    expect(Array.isArray(progress.body.days)).toBe(true);
    expect(progress.body.days.length).toBe(5);
    expect(progress.body.streaks.currentDays).toBe(2);
    expect(progress.body.streaks.longestDays).toBe(2);
    expect(typeof progress.body.weeklyDelta.calories.currentAvg).toBe('number');
    expect(typeof progress.body.weeklyDelta.protein.delta).toBe('number');

    const dayWithLogs = progress.body.days.find((day: { date: string }) => day.date === '2026-02-20');
    expect(dayWithLogs).toBeTruthy();
    expect(dayWithLogs.logsCount).toBeGreaterThan(0);
    expect(dayWithLogs.adherence.caloriesPct).toBeGreaterThan(0);

    const dayWithoutLogs = progress.body.days.find((day: { date: string }) => day.date === '2026-02-19');
    expect(dayWithoutLogs).toBeTruthy();
    expect(dayWithoutLogs.logsCount).toBe(0);
    expect(dayWithoutLogs.totals.calories).toBe(0);
    expect(dayWithoutLogs.adherence.caloriesPct).toBe(0);
  });

  test('progress endpoint matches day-summary totals for the same day and tz', async () => {
    const onboarding = await request(app)
      .post('/v1/onboarding')
      .set(authHeader)
      .send({
        goal: 'maintain',
        dietPreference: 'none',
        allergies: [],
        units: 'imperial',
        activityLevel: 'moderate',
        timezone: 'UTC'
      });

    expect(onboarding.status).toBe(200);

    const parse = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '1 egg',
        loggedAt: '2026-02-22T12:00:00.000Z'
      });

    expect(parse.status).toBe(200);

    const save = await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', 'e8d120db-6be8-4e41-ad9d-846d6f3ee056')
      .send({
        parseRequestId: parse.body.parseRequestId,
        parseVersion: parse.body.parseVersion,
        parsedLog: {
          rawText: '1 egg',
          loggedAt: '2026-02-22T12:00:00.000Z',
          confidence: parse.body.confidence,
          totals: parse.body.totals,
          items: parse.body.items
        }
      });

    expect(save.status).toBe(200);

    const [summary, progress] = await Promise.all([
      request(app)
        .get('/v1/logs/day-summary')
        .set(authHeader)
        .query({ date: '2026-02-22', tz: 'UTC' }),
      request(app)
        .get('/v1/logs/progress')
        .set(authHeader)
        .query({ from: '2026-02-22', to: '2026-02-22', tz: 'UTC' })
    ]);

    expect(summary.status).toBe(200);
    expect(progress.status).toBe(200);
    expect(progress.body.days.length).toBe(1);
    expect(progress.body.days[0].totals.calories).toBe(summary.body.totals.calories);
    expect(progress.body.days[0].totals.protein).toBe(summary.body.totals.protein);
    expect(progress.body.days[0].totals.carbs).toBe(summary.body.totals.carbs);
    expect(progress.body.days[0].totals.fat).toBe(summary.body.totals.fat);
  });

  test('validation errors return standard INVALID_INPUT envelope', async () => {
    const badOnboarding = await request(app)
      .post('/v1/onboarding')
      .set(authHeader)
      .send({
        goal: 'bulk',
        dietPreference: 'none',
        allergies: [],
        units: 'imperial',
        activityLevel: 'moderate'
      });

    expect(badOnboarding.status).toBe(400);
    expect(badOnboarding.body.error.code).toBe('INVALID_INPUT');
    expect(typeof badOnboarding.body.error.message).toBe('string');
    expect(badOnboarding.body.error.requestId).toBeTruthy();

    const tooLongText = 'a'.repeat(501);
    const badParse = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: tooLongText,
        loggedAt: '2026-02-15T13:35:00.000Z'
      });

    expect(badParse.status).toBe(400);
    expect(badParse.body.error.code).toBe('INVALID_INPUT');
    expect(badParse.body.error.message).toContain('max length');
    expect(badParse.body.error.requestId).toBeTruthy();

    const badSummary = await request(app)
      .get('/v1/logs/day-summary')
      .set(authHeader)
      .query({ date: '2026/02/15' });

    expect(badSummary.status).toBe(400);
    expect(badSummary.body.error.code).toBe('INVALID_INPUT');
    expect(typeof badSummary.body.error.message).toBe('string');
    expect(badSummary.body.error.requestId).toBeTruthy();

    const badProgress = await request(app)
      .get('/v1/logs/progress')
      .set(authHeader)
      .query({ from: '2026-02-20', to: '2026-02-10' });

    expect(badProgress.status).toBe(400);
    expect(badProgress.body.error.code).toBe('INVALID_INPUT');
    expect(typeof badProgress.body.error.message).toBe('string');
    expect(badProgress.body.error.requestId).toBeTruthy();
  });

  test('future-date parse is rejected', async () => {
    const parse = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '1 banana',
        loggedAt: '2099-01-01T12:00:00.000Z'
      });

    expect(parse.status).toBe(422);
    expect(parse.body.error.code).toBe('FUTURE_DATE_NOT_ALLOWED');
  });

  test('save blocks unresolved item unless manual override is supplied', async () => {
    const parse = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: 'custom test item',
        loggedAt: '2026-02-15T13:35:00.000Z'
      });

    expect(parse.status).toBe(200);

    const unresolvedPayload = {
      parseRequestId: parse.body.parseRequestId,
      parseVersion: parse.body.parseVersion,
      parsedLog: {
        rawText: 'custom test item',
        loggedAt: '2026-02-15T13:35:00.000Z',
        confidence: 0.9,
        totals: {
          calories: 120,
          protein: 6,
          carbs: 10,
          fat: 4
        },
        items: [
          {
            name: 'custom test item',
            quantity: 1,
            amount: 1,
            unit: 'count',
            unitNormalized: 'count',
            grams: 100,
            gramsPerUnit: 100,
            calories: 120,
            protein: 6,
            carbs: 10,
            fat: 4,
            nutritionSourceId: 'manual_test',
            matchConfidence: 0.4,
            needsClarification: true
          }
        ]
      }
    };

    const saveBlocked = await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', 'e4189d7f-a907-4bd5-93e6-145774f0dd20')
      .send(unresolvedPayload);

    expect(saveBlocked.status).toBe(422);
    expect(saveBlocked.body.error.code).toBe('NEEDS_CLARIFICATION');

    const resolvedPayload = {
      ...unresolvedPayload,
      parsedLog: {
        ...unresolvedPayload.parsedLog,
        items: unresolvedPayload.parsedLog.items.map((item) => ({
          ...item,
          manualOverride: {
            enabled: true,
            reason: 'User confirmed custom serving.',
            editedFields: ['quantity', 'calories']
          }
        }))
      }
    };

    const saveAllowed = await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', '1f72f012-53c6-49f3-98d8-0880fd592f5e')
      .send(resolvedPayload);

    expect(saveAllowed.status).toBe(200);
    expect(saveAllowed.body.status).toBe('saved');
  });

  test('auth failures return UNAUTHORIZED envelope', async () => {
    const missingBearer = await request(app)
      .post('/v1/logs/parse')
      .send({
        text: '1 egg',
        loggedAt: '2026-02-15T13:35:00.000Z'
      });

    expect(missingBearer.status).toBe(401);
    expect(missingBearer.body.error.code).toBe('UNAUTHORIZED');
    expect(typeof missingBearer.body.error.message).toBe('string');
    expect(missingBearer.body.error.requestId).toBeTruthy();

    const invalidBearer = await request(app)
      .get('/v1/logs/day-summary')
      .set({ Authorization: 'Bearer not-a-valid-dev-token' })
      .query({ date: '2026-02-15' });

    expect(invalidBearer.status).toBe(401);
    expect(invalidBearer.body.error.code).toBe('UNAUTHORIZED');
    expect(typeof invalidBearer.body.error.message).toBe('string');
    expect(invalidBearer.body.error.requestId).toBeTruthy();
  });

  test('medium-confidence text can use one fallback pass', async () => {
    const parse = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '2 egs, toast',
        loggedAt: '2026-02-15T11:00:00.000Z'
      });

    expect(parse.status).toBe(200);
    expect(typeof parse.body.fallbackUsed).toBe('boolean');
    expect(parse.body.fallbackUsed).toBe(true);
    expect(parse.body.fallbackModel).toBeTruthy();
    expect(parse.body.budget.userSoftCapExceeded).toBe(true);

    const fallbackRows = await pool.query<{
      feature: string;
      model: string;
      input_tokens: number;
      output_tokens: number;
      estimated_cost_usd: string;
    }>(
      `
      SELECT feature, model, input_tokens, output_tokens, estimated_cost_usd
      FROM ai_cost_events
      WHERE feature = 'parse_fallback'
      ORDER BY created_at DESC
      LIMIT 1
      `
    );

    expect(fallbackRows.rowCount).toBe(1);
    expect(fallbackRows.rows[0]?.feature).toBe('parse_fallback');
    expect(fallbackRows.rows[0]?.model).toBeTruthy();
    expect(Number(fallbackRows.rows[0]?.input_tokens || 0)).toBeGreaterThan(0);
    expect(Number(fallbackRows.rows[0]?.output_tokens || 0)).toBeGreaterThan(0);
    expect(Number(fallbackRows.rows[0]?.estimated_cost_usd || 0)).toBeGreaterThan(0);

    const perRequestFallbackCalls = await pool.query<{ c: string }>(
      `
      SELECT COUNT(*)::text AS c
      FROM ai_cost_events
      WHERE feature = 'parse_fallback'
        AND request_id = $1
      `,
      [parse.body.parseRequestId]
    );
    expect(Number(perRequestFallbackCalls.rows[0]?.c || 0)).toBe(1);
  });

  test('parse skips fallback when remaining daily budget is insufficient', async () => {
    const first = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '2 egs, toast',
        loggedAt: '2026-02-15T11:05:00.000Z'
      });

    expect(first.status).toBe(200);
    expect(first.body.fallbackUsed).toBe(true);

    const second = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '3 egs, toast',
        loggedAt: '2026-02-15T11:06:00.000Z'
      });

    expect(second.status).toBe(200);
    expect(second.body.fallbackUsed).toBe(false);
    expect(second.body.budget.fallbackAllowed).toBe(false);
  });

  test('low-confidence text returns clarification questions', async () => {
    const inputText = 'mystery blob from cafe';
    const parse = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: inputText,
        loggedAt: '2026-02-15T11:00:00.000Z'
      });

    expect(parse.status).toBe(200);
    expect(parse.body.needsClarification).toBe(true);
    expect(Array.isArray(parse.body.clarificationQuestions)).toBe(true);
    expect(parse.body.clarificationQuestions.length).toBeGreaterThan(0);
  });

  test('daily budget cap disables gemini fallback and keeps base pipeline available', async () => {
    const mediumFirst = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '2 egs, toast',
        loggedAt: '2026-02-15T11:00:00.000Z'
      });

    expect(mediumFirst.status).toBe(200);
    expect(mediumFirst.body.fallbackUsed).toBe(true);

    const mediumSecond = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '3 egs, toast',
        loggedAt: '2026-02-15T11:03:00.000Z'
      });

    expect(mediumSecond.status).toBe(200);
    expect(mediumSecond.body.fallbackUsed).toBe(false);
    expect(mediumSecond.body.budget.fallbackAllowed).toBe(false);
  });

  test('escalation succeeds for clarification-needed parse requests', async () => {
    const low = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: 'mystery blob from cafe',
        loggedAt: '2026-02-15T11:00:00.000Z'
      });

    expect(low.status).toBe(200);
    expect(low.body.needsClarification).toBe(true);

    const escalation = await request(app)
      .post('/v1/logs/parse/escalate')
      .set(authHeader)
      .send({
        parseRequestId: low.body.parseRequestId,
        loggedAt: '2026-02-15T11:00:00.000Z'
      });

    expect(escalation.status).toBe(200);
    expect(escalation.body.route).toBe('escalation');
    expect(escalation.body.escalationUsed).toBe(true);
    expect(escalation.body.parseRequestId).toBe(low.body.parseRequestId);

    const costRows = await pool.query<{ c: string }>(
      `SELECT COUNT(*)::text AS c FROM ai_cost_events WHERE feature = 'escalation'`
    );
    expect(Number(costRows.rows[0]?.c || 0)).toBe(1);
  });

  test('idempotency replay returns prior success and no duplicate log', async () => {
    const parse = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '1 egg',
        loggedAt: '2026-02-15T11:30:00.000Z'
      });

    const payload = {
      parseRequestId: parse.body.parseRequestId,
      parseVersion: parse.body.parseVersion,
      parsedLog: {
        rawText: '1 egg',
        loggedAt: '2026-02-15T11:30:00.000Z',
        confidence: parse.body.confidence,
        totals: parse.body.totals,
        items: parse.body.items
      }
    };

    const first = await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', '64d472f3-fba6-4a42-be42-14f159411f80')
      .send(payload);
    const second = await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', '64d472f3-fba6-4a42-be42-14f159411f80')
      .send(payload);

    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(second.body.logId).toBe(first.body.logId);
    expect(first.body.healthSync?.syncMode).toBe('per-log');
    expect(second.body.healthSync?.syncMode).toBe('per-log');
    expect(second.body.healthSync?.healthWriteKey).toBe(first.body.healthSync?.healthWriteKey);

    const logs = await pool.query<{ c: string }>('SELECT COUNT(*)::text AS c FROM food_logs WHERE user_id = $1', [userId]);
    expect(Number(logs.rows[0]?.c || 0)).toBe(1);
  });

  test('idempotency key reuse with different payload is rejected', async () => {
    const parse = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '1 egg',
        loggedAt: '2026-02-15T11:30:00.000Z'
      });

    const firstPayload = {
      parseRequestId: parse.body.parseRequestId,
      parseVersion: parse.body.parseVersion,
      parsedLog: {
        rawText: '1 egg',
        loggedAt: '2026-02-15T11:30:00.000Z',
        confidence: parse.body.confidence,
        totals: parse.body.totals,
        items: parse.body.items
      }
    };

    const secondPayload = {
      ...firstPayload,
      parsedLog: {
        ...firstPayload.parsedLog,
        rawText: '2 eggs'
      }
    };

    await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', '79974465-88d7-4afd-bcb3-f4e90915b9c1')
      .send(firstPayload);

    const second = await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', '79974465-88d7-4afd-bcb3-f4e90915b9c1')
      .send(secondPayload);

    expect(second.status).toBe(409);
    expect(second.body.error.code).toBe('IDEMPOTENCY_CONFLICT');
  });

  test('unknown parseRequestId is rejected on save', async () => {
    const save = await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', '31ab444a-fc19-438f-b8ed-7ccad3f4e667')
      .send({
        parseRequestId: 'unknown-req',
        parseVersion: 'invalid_version',
        parsedLog: {
          rawText: '1 egg',
          loggedAt: '2026-02-15T11:30:00.000Z',
          confidence: 0.9,
          totals: { calories: 72, protein: 6.3, carbs: 0.6, fat: 4.8 },
          items: [
            {
              name: 'egg',
              quantity: 1,
              unit: 'count',
              grams: 50,
              calories: 72,
              protein: 6.3,
              carbs: 0.6,
              fat: 4.8,
              nutritionSourceId: 'seed_egg',
              matchConfidence: 1
            }
          ]
        }
      });

    expect(save.status).toBe(422);
    expect(save.body.error.code).toBe('INVALID_PARSE_REFERENCE');
  });

  test('save rejects valid parseRequestId when parseVersion mismatches', async () => {
    const parse = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '1 egg',
        loggedAt: '2026-02-15T11:30:00.000Z'
      });

    expect(parse.status).toBe(200);

    const save = await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', '0f9ae8c2-5489-4d42-9add-b8d7289d0b2c')
      .send({
        parseRequestId: parse.body.parseRequestId,
        parseVersion: 'v999',
        parsedLog: {
          rawText: '1 egg',
          loggedAt: '2026-02-15T11:30:00.000Z',
          confidence: parse.body.confidence,
          totals: parse.body.totals,
          items: parse.body.items
        }
      });

    expect(save.status).toBe(422);
    expect(save.body.error.code).toBe('INVALID_PARSE_REFERENCE');
  });

  test('save rejects stale parseRequestId by TTL', async () => {
    const parse = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '1 egg',
        loggedAt: '2026-02-15T11:30:00.000Z'
      });

    expect(parse.status).toBe(200);

    await pool.query(
      `
      UPDATE parse_requests
      SET created_at = NOW() - INTERVAL '48 hours'
      WHERE request_id = $1
      `,
      [parse.body.parseRequestId]
    );

    const save = await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', '97a6f3a8-22af-447f-809f-735a5f8779d6')
      .send({
        parseRequestId: parse.body.parseRequestId,
        parseVersion: parse.body.parseVersion,
        parsedLog: {
          rawText: '1 egg',
          loggedAt: '2026-02-15T11:30:00.000Z',
          confidence: parse.body.confidence,
          totals: parse.body.totals,
          items: parse.body.items
        }
      });

    expect(save.status).toBe(422);
    expect(save.body.error.code).toBe('INVALID_PARSE_REFERENCE');
  });

  test('future-date save is rejected by timezone guard', async () => {
    const parse = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '1 egg',
        loggedAt: '2026-02-15T11:30:00.000Z'
      });

    expect(parse.status).toBe(200);

    const save = await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', '24c80e9f-07a8-4e38-8aef-061a6ef6ca2e')
      .send({
        parseRequestId: parse.body.parseRequestId,
        parseVersion: parse.body.parseVersion,
        parsedLog: {
          rawText: '1 egg',
          loggedAt: '2099-01-01T12:00:00.000Z',
          confidence: parse.body.confidence,
          totals: parse.body.totals,
          items: parse.body.items
        }
      });

    expect(save.status).toBe(422);
    expect(save.body.error.code).toBe('FUTURE_DATE_NOT_ALLOWED');
  });

  test('save endpoint rolls back atomically when item insert fails', async () => {
    await pool.query('DROP TRIGGER IF EXISTS fail_food_log_items_insert ON food_log_items');
    await pool.query('DROP FUNCTION IF EXISTS fail_food_log_items_insert_fn()');
    await pool.query(`
      CREATE FUNCTION fail_food_log_items_insert_fn()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'forced food_log_items failure for rollback test';
      END;
      $$;
    `);
    await pool.query(`
      CREATE TRIGGER fail_food_log_items_insert
      BEFORE INSERT ON food_log_items
      FOR EACH ROW
      EXECUTE FUNCTION fail_food_log_items_insert_fn();
    `);

    try {
      const parse = await request(app)
        .post('/v1/logs/parse')
        .set(authHeader)
        .send({
          text: '1 egg',
          loggedAt: '2026-02-15T11:30:00.000Z'
        });

      expect(parse.status).toBe(200);

      const save = await request(app)
        .post('/v1/logs')
        .set(authHeader)
        .set('Idempotency-Key', '0542fb2b-329f-48e7-adf1-32a67cdaef85')
        .send({
          parseRequestId: parse.body.parseRequestId,
          parseVersion: parse.body.parseVersion,
          parsedLog: {
            rawText: '1 egg',
            loggedAt: '2026-02-15T11:30:00.000Z',
            confidence: parse.body.confidence,
            totals: parse.body.totals,
            items: parse.body.items
          }
        });

      expect(save.status).toBe(500);
      expect(save.body.error.code).toBe('INTERNAL_ERROR');

      const logs = await pool.query<{ c: string }>('SELECT COUNT(*)::text AS c FROM food_logs WHERE user_id = $1', [userId]);
      expect(Number(logs.rows[0]?.c || 0)).toBe(0);

      const idempotencyRows = await pool.query<{ c: string }>(
        'SELECT COUNT(*)::text AS c FROM log_save_idempotency WHERE user_id = $1',
        [userId]
      );
      expect(Number(idempotencyRows.rows[0]?.c || 0)).toBe(0);
    } finally {
      await pool.query('DROP TRIGGER IF EXISTS fail_food_log_items_insert ON food_log_items');
      await pool.query('DROP FUNCTION IF EXISTS fail_food_log_items_insert_fn()');
    }
  });

  test('internal metrics endpoint is key-protected and returns required metrics', async () => {
    const noKey = await request(app).get('/v1/internal/metrics');
    expect(noKey.status).toBe(403);

    await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '2 egs, toast',
        loggedAt: '2026-02-15T12:00:00.000Z'
      });

    const metrics = await request(app)
      .get('/v1/internal/metrics')
      .set('x-internal-metrics-key', 'metrics-test-key');

    expect(metrics.status).toBe(200);
    expect(metrics.body.generatedAt).toBeTruthy();
    expect(metrics.body.metrics).toHaveProperty('parse_requests_total');
    expect(metrics.body.metrics).toHaveProperty('parse_fallback_total');
    expect(metrics.body.metrics).toHaveProperty('parse_escalation_total');
    expect(metrics.body.metrics).toHaveProperty('parse_clarification_total');
    expect(metrics.body.metrics).toHaveProperty('ai_tokens_input_total');
    expect(metrics.body.metrics).toHaveProperty('ai_tokens_output_total');
    expect(metrics.body.metrics).toHaveProperty('ai_estimated_cost_usd_total');
    expect(metrics.body.metrics).toHaveProperty('cache_hit_ratio');
    expect(metrics.body.metrics.parse_requests_total).toBeGreaterThan(0);
  });

  test('internal alerts endpoint evaluates thresholds and includes runbook links', async () => {
    const noKey = await request(app).get('/v1/internal/alerts');
    expect(noKey.status).toBe(403);

    const parseForSave = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: '1 egg',
        loggedAt: '2026-02-15T12:10:00.000Z'
      });
    expect(parseForSave.status).toBe(200);

    const save = await request(app)
      .post('/v1/logs')
      .set(authHeader)
      .set('Idempotency-Key', 'ca39031b-9498-4f4a-9708-a9a3db7b54ed')
      .send({
        parseRequestId: parseForSave.body.parseRequestId,
        parseVersion: parseForSave.body.parseVersion,
        parsedLog: {
          rawText: '1 egg',
          loggedAt: '2026-02-15T12:10:00.000Z',
          confidence: parseForSave.body.confidence,
          totals: parseForSave.body.totals,
          items: parseForSave.body.items
        }
      });
    expect(save.status).toBe(200);

    const low = await request(app)
      .post('/v1/logs/parse')
      .set(authHeader)
      .send({
        text: 'mystery blob from cafe',
        loggedAt: '2026-02-15T12:11:00.000Z'
      });
    expect(low.status).toBe(200);
    expect(low.body.needsClarification).toBe(true);

    const alerts = await request(app)
      .get('/v1/internal/alerts')
      .set('x-internal-metrics-key', 'metrics-test-key');

    expect(alerts.status).toBe(200);
    expect(alerts.body.generatedAt).toBeTruthy();
    expect(Array.isArray(alerts.body.alerts)).toBe(true);
    expect(alerts.body.hasActiveAlerts).toBe(true);

    const escalationAlert = alerts.body.alerts.find((alert: { key: string }) => alert.key === 'ESCALATION_RATE_HIGH');
    const cacheAlert = alerts.body.alerts.find((alert: { key: string }) => alert.key === 'CACHE_HIT_RATIO_LOW');
    const costAlert = alerts.body.alerts.find((alert: { key: string }) => alert.key === 'COST_PER_LOG_DRIFT_HIGH');

    expect(escalationAlert?.triggered).toBe(false);
    expect(cacheAlert?.triggered).toBe(true);
    expect(typeof costAlert?.triggered).toBe('boolean');

    expect(escalationAlert?.runbook).toContain('/docs/ALERT_RUNBOOK_MVP.md#escalation-rate-high');
    expect(cacheAlert?.runbook).toContain('/docs/ALERT_RUNBOOK_MVP.md#cache-hit-ratio-low');
    expect(costAlert?.runbook).toContain('/docs/ALERT_RUNBOOK_MVP.md#cost-per-log-drift-high');
  });
});

if (!hasTestDb) {
  console.warn('Skipping integration tests because DATABASE_URL_TEST is not set.');
}
