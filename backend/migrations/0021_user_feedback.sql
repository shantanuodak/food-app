-- User-submitted feedback collected via in-app form on the profile screen.
-- This is product feedback, not bug-tracker tickets; the testing dashboard
-- surfaces a list view for triage.

CREATE TABLE IF NOT EXISTS user_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    user_email TEXT,
    message TEXT NOT NULL CHECK (length(message) >= 1 AND length(message) <= 4000),
    app_version TEXT,
    build_number TEXT,
    device_model TEXT,
    os_version TEXT,
    locale TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Drive the dashboard's newest-first list view.
CREATE INDEX IF NOT EXISTS idx_user_feedback_created_at
    ON user_feedback(created_at DESC);

-- Per-user lookup for support cases ("show me everything Jane reported").
CREATE INDEX IF NOT EXISTS idx_user_feedback_user_created_at
    ON user_feedback(user_id, created_at DESC);
