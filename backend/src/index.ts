import { config } from './config.js';
import { createApp } from './app.js';
import { assertRequiredSchema } from './db/schemaAssertions.js';
import { runNotificationSweep } from './services/notificationService.js';

async function boot(): Promise<void> {
  await assertRequiredSchema();
  console.log('[boot] Schema assertions passed.');

  const app = createApp();
  app.listen(config.port, () => {
    console.log(`Backend listening on port ${config.port}`);
  });

  if (config.notificationRunnerEnabled) {
    const run = async () => {
      try {
        const summary = await runNotificationSweep();
        console.log('[notifications] sweep complete', summary);
      } catch (error) {
        console.error('[notifications] sweep failed', error);
      }
    };
    setInterval(() => void run(), Math.max(60_000, config.notificationRunnerIntervalMs)).unref();
    void run();
  }
}

boot().catch((error) => {
  console.error('[FATAL] Backend startup failed', error);
  process.exit(1);
});
