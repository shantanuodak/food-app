import { AsyncLocalStorage } from 'node:async_hooks';
import { Pool, type PoolClient, type QueryResult } from 'pg';
import { config } from './config.js';

function shouldUseSsl(connectionString: string, configuredSsl: boolean): boolean {
  if (!configuredSsl) {
    return false;
  }

  try {
    const url = new URL(connectionString);
    const host = (url.hostname || '').toLowerCase();
    if (host === 'localhost' || host === '127.0.0.1' || host === '::1') {
      return false;
    }
  } catch {
    // If connection string is malformed, keep previous configured behavior.
  }

  return true;
}

function connectionUser(connectionString: string): string {
  try {
    const url = new URL(connectionString);
    return (url.username || '').toLowerCase();
  } catch {
    return '';
  }
}

function enforceRlsSafeRole(connectionString: string): void {
  if (!config.rlsStrictMode) {
    return;
  }
  if (config.authMode === 'dev') {
    return;
  }

  const dbUser = connectionUser(connectionString);
  if (dbUser === 'postgres') {
    throw new Error('RLS_STRICT_MODE=true requires a non-postgres database role');
  }
}

enforceRlsSafeRole(config.databaseUrl);

export type DbAuthContext = {
  userId: string;
  authProvider: 'dev' | 'supabase';
  email: string | null;
  isAdmin: boolean;
};

const dbAuthContextStorage = new AsyncLocalStorage<DbAuthContext | null>();

export function runWithDbAuthContext<T>(context: DbAuthContext, callback: () => T): T {
  return dbAuthContextStorage.run(context, callback);
}

function currentDbAuthContext(): DbAuthContext | null {
  return dbAuthContextStorage.getStore() ?? null;
}

function roleClaimFromContext(context: DbAuthContext | null): string {
  if (!context) {
    return '';
  }
  if (context.isAdmin) {
    return 'admin';
  }
  return context.authProvider === 'supabase' ? 'authenticated' : 'dev';
}

async function applySessionClaims(client: PoolClient, context: DbAuthContext | null): Promise<void> {
  await client.query(
    `
    SELECT
      set_config('request.jwt.claim.sub', $1, false),
      set_config('request.jwt.claim.role', $2, false),
      set_config('request.jwt.claim.email', $3, false)
    `,
    [context?.userId ?? '', roleClaimFromContext(context), context?.email ?? '']
  );
}

export const pool = new Pool({
  connectionString: config.databaseUrl,
  // Keep the app pool explicit so Render instance count and Supabase limits
  // can be tuned together. The default remains pg's 10 connections; override
  // DATABASE_POOL_MAX if another consumer or instance type changes capacity.
  max: config.databasePoolMax,
  ssl: shouldUseSsl(config.databaseUrl, config.databaseSsl) ? { rejectUnauthorized: false } : undefined
});

const rawPoolConnect = pool.connect.bind(pool);

async function connectWithContext(): Promise<PoolClient> {
  const client = await rawPoolConnect();
  try {
    await applySessionClaims(client, currentDbAuthContext());
    return client;
  } catch (err) {
    client.release();
    throw err;
  }
}

async function queryWithContext(...args: unknown[]): Promise<QueryResult> {
  if (typeof args[args.length - 1] === 'function') {
    throw new Error('Callback-style pg queries are not supported');
  }

  if (args.length === 0) {
    throw new Error('pool.query requires a SQL text or query config');
  }

  const client = await connectWithContext();
  try {
    return await (client.query as (...queryArgs: unknown[]) => Promise<QueryResult>)(...args);
  } finally {
    client.release();
  }
}

// Ensure all pool-level queries run with request-scoped RLS claims.
(pool as unknown as { connect: typeof connectWithContext }).connect = connectWithContext;
(pool as unknown as { query: typeof queryWithContext }).query = queryWithContext;
