ALTER TABLE parse_requests
  ADD COLUMN IF NOT EXISTS parse_result_json JSONB;
