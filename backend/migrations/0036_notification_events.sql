CREATE TABLE IF NOT EXISTS notification_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    delivery_id UUID REFERENCES notification_deliveries(id) ON DELETE SET NULL,
    template_key TEXT NOT NULL REFERENCES notification_templates(template_key),
    delivery_key TEXT NOT NULL,
    destination TEXT NOT NULL CHECK (destination IN ('voice', 'text', 'camera', 'streaks', 'reminders', 'home')),
    event_type TEXT NOT NULL CHECK (event_type IN ('opened', 'action_tapped', 'snoozed')),
    action_identifier TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, delivery_key, event_type, action_identifier)
);

ALTER TABLE notification_events ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_notification_events_delivery_created
    ON notification_events(delivery_key, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_events_template_created
    ON notification_events(template_key, created_at DESC);
