-- Add unresolved route to parse_requests constraint

ALTER TABLE parse_requests
  DROP CONSTRAINT IF EXISTS parse_requests_primary_route_check;

UPDATE parse_requests
SET primary_route = 'gemini'
WHERE primary_route IS NULL
   OR btrim(primary_route) = ''
   OR primary_route NOT IN ('cache', 'deterministic', 'alias', 'fatsecret', 'gemini', 'unresolved');

ALTER TABLE parse_requests
  ADD CONSTRAINT parse_requests_primary_route_check
  CHECK (primary_route IN ('cache', 'deterministic', 'alias', 'fatsecret', 'gemini', 'unresolved'));
