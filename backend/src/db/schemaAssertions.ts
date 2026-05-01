import { pool } from '../db.js';

type RequiredColumn = {
  table: string;
  column: string;
  migration: string;
};

const requiredColumns: RequiredColumn[] = [
  { table: 'food_logs', column: 'parse_request_id', migration: '0017_food_log_parse_provenance.sql' },
  { table: 'food_logs', column: 'image_ref', migration: '0012_image_log_fields.sql' },
  { table: 'food_logs', column: 'input_kind', migration: '0012_image_log_fields.sql' },
  { table: 'log_save_idempotency', column: 'log_id', migration: '0002_parse_contracts.sql' },
  { table: 'save_attempts', column: 'outcome', migration: '0019_save_attempts.sql' },
  { table: 'save_attempts', column: 'parse_request_id', migration: '0019_save_attempts.sql' }
];

const requiredIndexNames = ['idx_food_logs_user_parse_request_unique', 'food_logs_user_parse_request_unique'];

export async function assertRequiredSchema(): Promise<void> {
  for (const requirement of requiredColumns) {
    const result = await pool.query<{ ok: number }>(
      `
      SELECT 1 AS ok
      FROM information_schema.columns
      WHERE table_name = $1
        AND column_name = $2
      LIMIT 1
      `,
      [requirement.table, requirement.column]
    );

    if ((result.rowCount ?? 0) === 0) {
      throw new Error(
        `[FATAL] Schema assertion failed: ${requirement.table}.${requirement.column} missing (need migration ${requirement.migration})`
      );
    }
  }

  const indexResult = await pool.query<{ indexname: string }>(
    `
    SELECT indexname
    FROM pg_indexes
    WHERE schemaname = ANY (current_schemas(true))
      AND indexname = ANY($1::text[])
    LIMIT 1
    `,
    [requiredIndexNames]
  );

  if ((indexResult.rowCount ?? 0) === 0) {
    throw new Error(
      `[FATAL] Schema assertion failed: expected one of [${requiredIndexNames.join(
        ', '
      )}] for migration 0018_food_logs_parse_request_unique.sql`
    );
  }
}
