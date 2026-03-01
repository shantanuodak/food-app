import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from '../db.js';
import { runMigrations } from '../db/migrations.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const migrationsDir = path.resolve(__dirname, '../../migrations');

async function run(): Promise<void> {
  await runMigrations(pool, migrationsDir);

  await pool.end();
  console.log('Migrations complete');
}

run().catch(async (err) => {
  console.error('Migration failed', err);
  await pool.end();
  process.exit(1);
});
