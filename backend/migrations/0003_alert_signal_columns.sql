-- Alert signal columns for anomaly detection windows
-- Date: 2026-02-16

ALTER TABLE parse_requests
  ADD COLUMN IF NOT EXISTS cache_hit BOOLEAN NOT NULL DEFAULT FALSE;
