-- Add FatSecret route to parse_requests route constraint
-- Date: 2026-02-28

ALTER TABLE parse_requests
  DROP CONSTRAINT IF EXISTS parse_requests_primary_route_check;

ALTER TABLE parse_requests
  ADD CONSTRAINT parse_requests_primary_route_check
  CHECK (primary_route IN ('cache', 'deterministic', 'alias', 'fatsecret', 'gemini'));
