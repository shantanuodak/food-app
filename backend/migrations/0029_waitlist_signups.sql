-- Public website waitlist signups.
-- This is intentionally separate from app users: people can join before
-- downloading or creating an account.

CREATE TABLE IF NOT EXISTS waitlist_signups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL CHECK (length(email) <= 320),
    email_normalized TEXT NOT NULL CHECK (length(email_normalized) <= 320),
    source TEXT NOT NULL DEFAULT 'website' CHECK (length(source) >= 1 AND length(source) <= 80),
    user_agent TEXT CHECK (user_agent IS NULL OR length(user_agent) <= 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_waitlist_signups_email_normalized
    ON waitlist_signups(email_normalized);

CREATE INDEX IF NOT EXISTS idx_waitlist_signups_created_at
    ON waitlist_signups(created_at DESC);
