-- Keep save_attempts diagnostic-only. Telemetry must never fail because the
-- referenced user/log row does not exist yet or was cleaned up by tests/tools.

ALTER TABLE save_attempts
    DROP CONSTRAINT IF EXISTS save_attempts_user_id_fkey,
    DROP CONSTRAINT IF EXISTS save_attempts_log_id_fkey;
