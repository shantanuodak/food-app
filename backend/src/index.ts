import { config } from './config.js';
import { createApp } from './app.js';
import { assertRequiredSchema } from './db/schemaAssertions.js';

async function boot(): Promise<void> {
  await assertRequiredSchema();
  console.log('[boot] Schema assertions passed.');

  const app = createApp();
  app.listen(config.port, () => {
    console.log(`Backend listening on port ${config.port}`);
  });
}

boot().catch((error) => {
  console.error('[FATAL] Backend startup failed', error);
  process.exit(1);
});
