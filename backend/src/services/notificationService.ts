import crypto from 'crypto';
import http2 from 'http2';
import { config } from '../config.js';
import { pool } from '../db.js';

export type NotificationDestination = 'voice' | 'text' | 'camera' | 'streaks' | 'reminders' | 'home';
export type NotificationKind = 'meal' | 'engagement' | 'discovery';

export type NotificationPreferenceInput = {
  timezone: string;
  remindersEnabled: boolean;
  breakfastEnabled: boolean;
  lunchEnabled: boolean;
  dinnerEnabled: boolean;
  breakfastStart: string;
  breakfastEnd: string;
  lunchStart: string;
  lunchEnd: string;
  dinnerStart: string;
  dinnerEnd: string;
  eatingWindowEnabled: boolean;
  eatingWindowStart: string;
  eatingWindowEnd: string;
  engagementEnabled?: boolean;
  discoveryEnabled?: boolean;
};

export type NotificationDeviceInput = {
  token: string;
  platform: 'ios';
  environment: 'development' | 'production';
  appVersion?: string | null;
  buildNumber?: string | null;
  deviceModel?: string | null;
  osVersion?: string | null;
  locale?: string | null;
};

export type NotificationTemplateInput = {
  kind: NotificationKind;
  title: string;
  body: string;
  destination: NotificationDestination;
  isEnabled: boolean;
};

type TemplateRow = {
  template_key: string;
  kind: NotificationKind;
  title: string;
  body: string;
  destination: NotificationDestination;
  is_enabled: boolean;
  updated_at: Date;
};

type PreferenceRow = {
  user_id: string;
  timezone: string;
  reminders_enabled: boolean;
  breakfast_enabled: boolean;
  lunch_enabled: boolean;
  dinner_enabled: boolean;
  breakfast_start: string;
  breakfast_end: string;
  lunch_start: string;
  lunch_end: string;
  dinner_start: string;
  dinner_end: string;
  eating_window_enabled: boolean;
  eating_window_start: string;
  eating_window_end: string;
  engagement_enabled: boolean;
  discovery_enabled: boolean;
};

type DeviceRow = {
  id: string;
  token: string;
  environment: 'development' | 'production';
};

type CandidateRow = PreferenceRow & {
  last_log_at: Date | null;
};

type ApnsResult = { apnsId?: string | null; error?: string | null };

const mealConfigs = [
  {
    mealKey: 'breakfast',
    templateKey: 'meal.breakfast',
    enabledColumn: 'breakfast_enabled',
    startColumn: 'breakfast_start',
    endColumn: 'breakfast_end'
  },
  {
    mealKey: 'lunch',
    templateKey: 'meal.lunch',
    enabledColumn: 'lunch_enabled',
    startColumn: 'lunch_start',
    endColumn: 'lunch_end'
  },
  {
    mealKey: 'dinner',
    templateKey: 'meal.dinner',
    enabledColumn: 'dinner_enabled',
    startColumn: 'dinner_start',
    endColumn: 'dinner_end'
  }
] as const;

function mapTemplate(row: TemplateRow) {
  return {
    templateKey: row.template_key,
    kind: row.kind,
    title: row.title,
    body: row.body,
    destination: row.destination,
    isEnabled: row.is_enabled,
    updatedAt: row.updated_at.toISOString()
  };
}

function normalizeTime(value: string): string {
  const match = value.match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return value;
  return `${match[1]!.padStart(2, '0')}:${match[2]}`;
}

function localParts(date: Date, timezone: string): { date: string; minutes: number } {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone || 'America/New_York',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23'
  }).formatToParts(date);
  const get = (type: string) => parts.find((part) => part.type === type)?.value || '00';
  return {
    date: `${get('year')}-${get('month')}-${get('day')}`,
    minutes: Number(get('hour')) * 60 + Number(get('minute'))
  };
}

function minutesFromTime(value: string): number {
  const [hour, minute] = value.split(':').map((part) => Number(part));
  return (Number.isFinite(hour) ? hour : 0) * 60 + (Number.isFinite(minute) ? minute : 0);
}

function isWithinWindow(nowMinutes: number, start: string, end: string): boolean {
  const startMinutes = minutesFromTime(start);
  const endMinutes = minutesFromTime(end);
  if (startMinutes <= endMinutes) {
    return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
  }
  return nowMinutes >= startMinutes || nowMinutes <= endMinutes;
}

function base64url(input: Buffer | string): string {
  return Buffer.from(input).toString('base64url');
}

let cachedApnsToken: { value: string; expiresAt: number } | null = null;

function apnsJwt(): string {
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (cachedApnsToken && cachedApnsToken.expiresAt > nowSeconds + 60) {
    return cachedApnsToken.value;
  }
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: config.apnsKeyId }));
  const claims = base64url(JSON.stringify({ iss: config.apnsTeamId, iat: nowSeconds }));
  const signer = crypto.createSign('SHA256');
  signer.update(`${header}.${claims}`);
  signer.end();
  const signature = signer
    .sign({ key: config.apnsPrivateKey, dsaEncoding: 'ieee-p1363' })
    .toString('base64url');
  const value = `${header}.${claims}.${signature}`;
  cachedApnsToken = { value, expiresAt: nowSeconds + 50 * 60 };
  return value;
}

function apnsIsConfigured(): boolean {
  return Boolean(config.apnsEnabled && config.apnsTeamId && config.apnsKeyId && config.apnsPrivateKey && config.apnsBundleId);
}

async function sendApns(device: DeviceRow, template: TemplateRow, deliveryKey: string): Promise<ApnsResult> {
  if (!apnsIsConfigured()) {
    return { error: 'APNS_NOT_CONFIGURED' };
  }

  const host = device.environment === 'production' ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com';
  const payload = JSON.stringify({
    aps: {
      alert: { title: template.title, body: template.body },
      sound: 'default',
      category:
        template.kind === 'meal'
          ? 'food-app.category.meal-reminder'
          : template.kind === 'discovery'
            ? 'food-app.category.discovery'
            : 'food-app.category.engagement'
    },
    destination: template.destination,
    templateKey: template.template_key,
    deliveryKey
  });

  return new Promise((resolve) => {
    const client = http2.connect(host);
    const request = client.request({
      ':method': 'POST',
      ':path': `/3/device/${device.token}`,
      authorization: `bearer ${apnsJwt()}`,
      'apns-topic': config.apnsBundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10'
    });
    let responseBody = '';
    let status = 0;
    let apnsId: string | null = null;

    request.setEncoding('utf8');
    request.on('response', (headers) => {
      status = Number(headers[':status'] || 0);
      const id = headers['apns-id'];
      apnsId = Array.isArray(id) ? id[0] || null : id || null;
    });
    request.on('data', (chunk) => {
      responseBody += chunk;
    });
    request.on('error', (error) => {
      client.close();
      resolve({ error: error.message });
    });
    request.on('end', () => {
      client.close();
      if (status >= 200 && status < 300) {
        resolve({ apnsId });
      } else {
        resolve({ apnsId, error: responseBody || `APNS_STATUS_${status}` });
      }
    });
    request.end(payload);
  });
}

export async function registerNotificationDevice(userId: string, input: NotificationDeviceInput) {
  const result = await pool.query(
    `
    INSERT INTO notification_devices (
      user_id, platform, token, environment, app_version, build_number,
      device_model, os_version, locale, is_active, last_seen_at, updated_at
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,TRUE,NOW(),NOW())
    ON CONFLICT (token) DO UPDATE
    SET user_id = EXCLUDED.user_id,
        platform = EXCLUDED.platform,
        environment = EXCLUDED.environment,
        app_version = EXCLUDED.app_version,
        build_number = EXCLUDED.build_number,
        device_model = EXCLUDED.device_model,
        os_version = EXCLUDED.os_version,
        locale = EXCLUDED.locale,
        is_active = TRUE,
        last_seen_at = NOW(),
        updated_at = NOW()
    RETURNING id
    `,
    [
      userId,
      input.platform,
      input.token,
      input.environment,
      input.appVersion || null,
      input.buildNumber || null,
      input.deviceModel || null,
      input.osVersion || null,
      input.locale || null
    ]
  );
  return { id: result.rows[0]?.id as string };
}

export async function deactivateNotificationDevice(userId: string, token: string): Promise<void> {
  await pool.query(
    `
    UPDATE notification_devices
    SET is_active = FALSE, updated_at = NOW()
    WHERE user_id = $1 AND token = $2
    `,
    [userId, token]
  );
}

export async function upsertNotificationPreferences(userId: string, input: NotificationPreferenceInput) {
  const result = await pool.query<PreferenceRow>(
    `
    INSERT INTO notification_preferences (
      user_id, timezone, reminders_enabled,
      breakfast_enabled, lunch_enabled, dinner_enabled,
      breakfast_start, breakfast_end, lunch_start, lunch_end, dinner_start, dinner_end,
      eating_window_enabled, eating_window_start, eating_window_end,
      engagement_enabled, discovery_enabled, updated_at
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,NOW())
    ON CONFLICT (user_id) DO UPDATE
    SET timezone = EXCLUDED.timezone,
        reminders_enabled = EXCLUDED.reminders_enabled,
        breakfast_enabled = EXCLUDED.breakfast_enabled,
        lunch_enabled = EXCLUDED.lunch_enabled,
        dinner_enabled = EXCLUDED.dinner_enabled,
        breakfast_start = EXCLUDED.breakfast_start,
        breakfast_end = EXCLUDED.breakfast_end,
        lunch_start = EXCLUDED.lunch_start,
        lunch_end = EXCLUDED.lunch_end,
        dinner_start = EXCLUDED.dinner_start,
        dinner_end = EXCLUDED.dinner_end,
        eating_window_enabled = EXCLUDED.eating_window_enabled,
        eating_window_start = EXCLUDED.eating_window_start,
        eating_window_end = EXCLUDED.eating_window_end,
        engagement_enabled = EXCLUDED.engagement_enabled,
        discovery_enabled = EXCLUDED.discovery_enabled,
        updated_at = NOW()
    RETURNING *
    `,
    [
      userId,
      input.timezone || 'America/New_York',
      input.remindersEnabled,
      input.breakfastEnabled,
      input.lunchEnabled,
      input.dinnerEnabled,
      normalizeTime(input.breakfastStart),
      normalizeTime(input.breakfastEnd),
      normalizeTime(input.lunchStart),
      normalizeTime(input.lunchEnd),
      normalizeTime(input.dinnerStart),
      normalizeTime(input.dinnerEnd),
      input.eatingWindowEnabled,
      normalizeTime(input.eatingWindowStart),
      normalizeTime(input.eatingWindowEnd),
      input.engagementEnabled ?? true,
      input.discoveryEnabled ?? true
    ]
  );
  return result.rows[0];
}

export async function listNotificationTemplates() {
  const result = await pool.query<TemplateRow>(
    `
    SELECT template_key, kind, title, body, destination, is_enabled, updated_at
    FROM notification_templates
    ORDER BY kind, template_key
    `
  );
  return result.rows.map(mapTemplate);
}

export async function updateNotificationTemplate(templateKey: string, input: NotificationTemplateInput) {
  const result = await pool.query<TemplateRow>(
    `
    UPDATE notification_templates
    SET kind = $2,
        title = $3,
        body = $4,
        destination = $5,
        is_enabled = $6,
        updated_at = NOW()
    WHERE template_key = $1
    RETURNING template_key, kind, title, body, destination, is_enabled, updated_at
    `,
    [templateKey, input.kind, input.title, input.body, input.destination, input.isEnabled]
  );
  return result.rows[0] ? mapTemplate(result.rows[0]) : null;
}

async function hasLoggedBetween(userId: string, localDate: string, start: string, end: string, timezone: string): Promise<boolean> {
  const result = await pool.query<{ ok: number }>(
    `
    SELECT 1 AS ok
    FROM food_logs
    WHERE user_id = $1
      AND logged_at >= (($2::date + $3::time) AT TIME ZONE $5)
      AND logged_at <= (($2::date + $4::time) AT TIME ZONE $5)
    LIMIT 1
    `,
    [userId, localDate, normalizeTime(start), normalizeTime(end), timezone]
  );
  return (result.rowCount || 0) > 0;
}

async function hasDelivery(userId: string, deliveryKey: string): Promise<boolean> {
  const result = await pool.query<{ ok: number }>(
    'SELECT 1 AS ok FROM notification_deliveries WHERE user_id = $1 AND delivery_key = $2 LIMIT 1',
    [userId, deliveryKey]
  );
  return (result.rowCount || 0) > 0;
}

async function activeDevices(userId: string): Promise<DeviceRow[]> {
  const result = await pool.query<DeviceRow>(
    `
    SELECT id, token, environment
    FROM notification_devices
    WHERE user_id = $1 AND is_active = TRUE
    ORDER BY last_seen_at DESC
    LIMIT 5
    `,
    [userId]
  );
  return result.rows;
}

async function deliver(userId: string, template: TemplateRow, deliveryKey: string, scheduledFor: Date): Promise<'sent' | 'skipped' | 'failed'> {
  if (!template.is_enabled) return 'skipped';
  if (await hasDelivery(userId, deliveryKey)) return 'skipped';
  const devices = await activeDevices(userId);
  if (devices.length === 0) {
    await recordDelivery(userId, null, template, deliveryKey, 'skipped', scheduledFor, null, 'NO_ACTIVE_DEVICE');
    return 'skipped';
  }

  let anySent = false;
  let lastError: string | null = null;
  for (const device of devices) {
    const result = await sendApns(device, template, deliveryKey);
    const status = result.error ? 'failed' : 'sent';
    lastError = result.error || null;
    await recordDelivery(userId, device.id, template, deliveryKey, status, scheduledFor, result.apnsId || null, result.error || null);
    if (!result.error) anySent = true;
  }
  return anySent ? 'sent' : lastError === 'APNS_NOT_CONFIGURED' ? 'skipped' : 'failed';
}

async function recordDelivery(
  userId: string,
  deviceId: string | null,
  template: TemplateRow,
  deliveryKey: string,
  status: 'sent' | 'skipped' | 'failed',
  scheduledFor: Date,
  apnsId: string | null,
  error: string | null
): Promise<void> {
  await pool.query(
    `
    INSERT INTO notification_deliveries (
      user_id, device_id, template_key, delivery_key, status, destination,
      scheduled_for, sent_at, apns_id, error_message
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
    ON CONFLICT (user_id, delivery_key) DO NOTHING
    `,
    [
      userId,
      deviceId,
      template.template_key,
      deliveryKey,
      status,
      template.destination,
      scheduledFor,
      status === 'sent' ? new Date() : null,
      apnsId,
      error
    ]
  );
}

export async function runNotificationSweep(now: Date = new Date()) {
  const templates = new Map<string, TemplateRow>();
  const templateRows = await pool.query<TemplateRow>(
    'SELECT template_key, kind, title, body, destination, is_enabled, updated_at FROM notification_templates WHERE is_enabled = TRUE'
  );
  for (const row of templateRows.rows) templates.set(row.template_key, row);

  const candidates = await pool.query<CandidateRow>(
    `
    SELECT
      p.user_id, p.timezone, p.reminders_enabled,
      p.breakfast_enabled, p.lunch_enabled, p.dinner_enabled,
      p.breakfast_start::text, p.breakfast_end::text,
      p.lunch_start::text, p.lunch_end::text,
      p.dinner_start::text, p.dinner_end::text,
      p.eating_window_enabled, p.eating_window_start::text, p.eating_window_end::text,
      p.engagement_enabled, p.discovery_enabled,
      MAX(fl.logged_at) AS last_log_at
    FROM notification_preferences p
    LEFT JOIN food_logs fl ON fl.user_id = p.user_id
    WHERE EXISTS (
      SELECT 1 FROM notification_devices d
      WHERE d.user_id = p.user_id AND d.is_active = TRUE
    )
    GROUP BY p.user_id
    `
  );

  const summary = { usersChecked: candidates.rowCount || 0, sent: 0, skipped: 0, failed: 0 };
  const bump = (status: 'sent' | 'skipped' | 'failed') => {
    summary[status] += 1;
  };

  for (const candidate of candidates.rows) {
    const timezone = candidate.timezone || 'America/New_York';
    const local = localParts(now, timezone);

    if (candidate.reminders_enabled) {
      for (const meal of mealConfigs) {
        const enabled = Boolean(candidate[meal.enabledColumn]);
        if (!enabled) continue;
        const start = String(candidate[meal.startColumn]);
        const end = String(candidate[meal.endColumn]);
        if (!isWithinWindow(local.minutes, start, end)) continue;
        const logged = await hasLoggedBetween(candidate.user_id, local.date, start, end, timezone);
        if (logged) continue;
        const template = templates.get(meal.templateKey);
        if (!template) continue;
        const status = await deliver(candidate.user_id, template, `${meal.templateKey}:${local.date}`, now);
        bump(status);
      }
    }

    if (candidate.engagement_enabled) {
      const hasLoggedToday = await hasLoggedBetween(candidate.user_id, local.date, '00:00', '23:59', timezone);
      const eod = templates.get('engagement.end_of_day');
      if (!hasLoggedToday && eod && local.minutes >= 20 * 60 + 45 && local.minutes <= 23 * 60) {
        bump(await deliver(candidate.user_id, eod, `engagement.end_of_day:${local.date}`, now));
      }

      const lastLogMs = candidate.last_log_at ? candidate.last_log_at.getTime() : 0;
      const inactiveHours = lastLogMs ? (now.getTime() - lastLogMs) / 3_600_000 : 9999;
      const r48 = templates.get('engagement.reactivation_48h');
      if (r48 && inactiveHours >= 48) {
        bump(await deliver(candidate.user_id, r48, `engagement.reactivation_48h:${local.date}`, now));
      } else {
        const r24 = templates.get('engagement.reactivation_24h');
        if (r24 && inactiveHours >= 24) {
          bump(await deliver(candidate.user_id, r24, `engagement.reactivation_24h:${local.date}`, now));
        }
      }
    }

    if (candidate.discovery_enabled) {
      const discovery = templates.get('discovery.logging_modes');
      if (discovery) {
        const weekdayKey = local.date.slice(0, 8);
        bump(await deliver(candidate.user_id, discovery, `discovery.logging_modes:${weekdayKey}`, now));
      }
    }
  }

  return summary;
}
