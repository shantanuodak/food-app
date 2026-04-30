-- Index supporting the save-health monitor.
--
-- The dashboard's `/save-health` endpoint groups recent activity per user
-- by joining parse_requests and food_logs on (user_id, created_at) within
-- a 7-day window. parse_requests already has
-- idx_parse_requests_user_created_at; food_logs only had
-- idx_food_logs_user_logged_at (logged_at, not created_at) — which is the
-- wrong sort key for "saves in the last N days at insertion time".
-- Without this index the monitor scans the table sequentially and balloons
-- past the 100ms target as save volume grows.

CREATE INDEX IF NOT EXISTS idx_food_logs_user_created_at
    ON food_logs(user_id, created_at DESC);
