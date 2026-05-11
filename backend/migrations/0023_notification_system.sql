-- Production notification system v1.
-- Stores APNs devices, user reminder preferences, CMS-editable templates,
-- and delivery history so server-side jobs can avoid duplicate nudges.

CREATE TABLE IF NOT EXISTS notification_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform TEXT NOT NULL CHECK (platform IN ('ios')),
    token TEXT NOT NULL UNIQUE,
    environment TEXT NOT NULL CHECK (environment IN ('development', 'production')),
    app_version TEXT,
    build_number TEXT,
    device_model TEXT,
    os_version TEXT,
    locale TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_devices_user_active
    ON notification_devices(user_id, is_active, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS notification_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    timezone TEXT NOT NULL DEFAULT 'America/New_York',
    reminders_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    breakfast_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    lunch_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    dinner_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    breakfast_start TIME NOT NULL DEFAULT '07:00',
    breakfast_end TIME NOT NULL DEFAULT '09:30',
    lunch_start TIME NOT NULL DEFAULT '11:30',
    lunch_end TIME NOT NULL DEFAULT '14:00',
    dinner_start TIME NOT NULL DEFAULT '18:00',
    dinner_end TIME NOT NULL DEFAULT '21:00',
    eating_window_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    eating_window_start TIME NOT NULL DEFAULT '08:00',
    eating_window_end TIME NOT NULL DEFAULT '20:00',
    engagement_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    discovery_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notification_templates (
    template_key TEXT PRIMARY KEY,
    kind TEXT NOT NULL CHECK (kind IN ('meal', 'engagement', 'discovery')),
    title TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
    body TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 240),
    destination TEXT NOT NULL CHECK (destination IN ('voice', 'text', 'camera', 'streaks', 'reminders', 'home')),
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO notification_templates (template_key, kind, title, body, destination)
VALUES
    ('meal.breakfast', 'meal', 'Breakfast check-in', 'Had breakfast? Say it, type it, or snap it before the details fade.', 'voice'),
    ('meal.lunch', 'meal', 'Lunch window check-in', 'What did lunch look like? A quick voice note is enough.', 'voice'),
    ('meal.dinner', 'meal', 'Dinner check-in', 'Future-you likes data. Log dinner while it is still fresh.', 'voice'),
    ('engagement.end_of_day', 'engagement', 'Still time to rescue today', 'One sentence beats a blank day. Your calorie map gets smarter when today is not a mystery.', 'voice'),
    ('engagement.reactivation_24h', 'engagement', 'Tiny check-in?', 'A rough log is still useful. Oats, coffee, and dal rice gives Food App something to calibrate.', 'voice'),
    ('engagement.reactivation_48h', 'engagement', 'No judgment, just a reset', 'Two quiet days happen. Want to log the last meal you remember and keep the streak alive-ish?', 'voice'),
    ('discovery.logging_modes', 'discovery', 'Food App shortcut', 'You can log by voice, text, or camera. Try whichever feels least annoying today.', 'camera')
ON CONFLICT (template_key) DO NOTHING;

CREATE TABLE IF NOT EXISTS notification_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID REFERENCES notification_devices(id) ON DELETE SET NULL,
    template_key TEXT NOT NULL REFERENCES notification_templates(template_key),
    delivery_key TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('sent', 'skipped', 'failed')),
    destination TEXT NOT NULL,
    scheduled_for TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at TIMESTAMPTZ,
    error_message TEXT,
    apns_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, delivery_key)
);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_user_created
    ON notification_deliveries(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_template_created
    ON notification_deliveries(template_key, created_at DESC);
