-- Parse request route attribution for metrics accuracy
-- Date: 2026-02-22

ALTER TABLE parse_requests
  ADD COLUMN IF NOT EXISTS primary_route TEXT;

UPDATE parse_requests
SET primary_route = CASE WHEN cache_hit THEN 'cache' ELSE 'deterministic' END
WHERE primary_route IS NULL
   OR btrim(primary_route) = '';

ALTER TABLE parse_requests
  ALTER COLUMN primary_route SET DEFAULT 'deterministic';

ALTER TABLE parse_requests
  ALTER COLUMN primary_route SET NOT NULL;

ALTER TABLE parse_requests
  DROP CONSTRAINT IF EXISTS parse_requests_primary_route_check;

ALTER TABLE parse_requests
  ADD CONSTRAINT parse_requests_primary_route_check
  CHECK (primary_route IN ('cache', 'deterministic', 'alias', 'gemini'));
