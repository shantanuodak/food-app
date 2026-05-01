-- Enforce one saved food_log per (user, parse_request_id) to eliminate
-- duplicate persisted rows when retries/races occur.

-- Keep the earliest row for each duplicate parse request; delete the rest.
DELETE FROM food_logs fl
USING (
  SELECT id
  FROM (
    SELECT
      id,
      ROW_NUMBER() OVER (
        PARTITION BY user_id, parse_request_id
        ORDER BY created_at ASC, id ASC
      ) AS rn
    FROM food_logs
    WHERE parse_request_id IS NOT NULL
  ) ranked
  WHERE rn > 1
) dup
WHERE fl.id = dup.id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_food_logs_user_parse_request_unique
  ON food_logs(user_id, parse_request_id)
  WHERE parse_request_id IS NOT NULL;
