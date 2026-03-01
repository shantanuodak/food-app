import { createHash } from 'node:crypto';

export type HealthSyncAction = 'upsert';
export type HealthSyncMode = 'per-log';

export type HealthSyncContract = {
  syncMode: HealthSyncMode;
  action: HealthSyncAction;
  healthWriteKey: string;
  dedupeStrategy: 'stable-per-log-id';
};

export function buildHealthWriteKey(userId: string, logId: string): string {
  return createHash('sha256').update(`health:v1:${userId}:${logId}`).digest('hex');
}

export function buildHealthSyncContract(userId: string, logId: string): HealthSyncContract {
  return {
    syncMode: 'per-log',
    action: 'upsert',
    healthWriteKey: buildHealthWriteKey(userId, logId),
    dedupeStrategy: 'stable-per-log-id'
  };
}

