-- Bug 2 (2026-05-22): editable display name on the Account screen.
-- Apple Sign In only returns the user's full name on FIRST sign-in, so
-- users who originally signed up without name capture (or whose first
-- sign-in dropped the name) have no way to set or correct it. iOS now
-- exposes a TextField backed by PATCH /v1/users/me.
--
-- Nullable so existing rows are untouched. The UI falls back to the
-- email prefix when display_name is NULL or empty.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS display_name TEXT;
