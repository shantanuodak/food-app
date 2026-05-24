-- Parse request analytics for image lanes
-- Date: 2026-05-24
--
-- Barcode and nutrition-label parses are distinct production lanes. The
-- routes already tag them separately, so the DB constraint needs to allow
-- the same values for parse_requests.primary_route.

ALTER TABLE parse_requests
  DROP CONSTRAINT IF EXISTS parse_requests_primary_route_check;

ALTER TABLE parse_requests
  ADD CONSTRAINT parse_requests_primary_route_check
  CHECK (primary_route IN ('cache', 'deterministic', 'alias', 'fatsecret', 'gemini', 'unresolved', 'barcode', 'label'));
