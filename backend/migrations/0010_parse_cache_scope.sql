-- Parse cache scope namespace for purge hooks and composite key visibility
-- Date: 2026-02-28

ALTER TABLE parse_cache
  ADD COLUMN IF NOT EXISTS cache_scope TEXT;

UPDATE parse_cache
SET cache_scope = COALESCE(NULLIF(cache_scope, ''), 'global')
WHERE cache_scope IS NULL
   OR cache_scope = '';

ALTER TABLE parse_cache
  ALTER COLUMN cache_scope SET DEFAULT 'global';

ALTER TABLE parse_cache
  ALTER COLUMN cache_scope SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_parse_cache_scope
  ON parse_cache(cache_scope);
