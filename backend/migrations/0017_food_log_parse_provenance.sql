-- Link saved food logs back to the parse request that produced them.
-- This makes diagnostics deterministic instead of relying on timestamp windows.

ALTER TABLE food_logs
  ADD COLUMN IF NOT EXISTS parse_request_id TEXT REFERENCES parse_requests(request_id) ON DELETE SET NULL;

ALTER TABLE food_logs
  ADD COLUMN IF NOT EXISTS parse_version TEXT;

CREATE INDEX IF NOT EXISTS idx_food_logs_parse_request_id
  ON food_logs(parse_request_id);

CREATE INDEX IF NOT EXISTS idx_food_logs_user_parse_request_id
  ON food_logs(user_id, parse_request_id);
