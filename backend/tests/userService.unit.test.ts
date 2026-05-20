import { describe, expect, test, vi, beforeEach, afterEach } from 'vitest';

describe('userService.ensureUserExists', () => {
  beforeEach(() => {
    vi.resetModules();
  });
  afterEach(() => {
    vi.resetModules();
  });

  test('uses provided email when identity supplies one', async () => {
    const query = vi.fn(async () => ({ rows: [] }));
    vi.doMock('../src/db.js', () => ({ pool: { query } }));
    const { ensureUserExists } = await import('../src/services/userService.js');

    await ensureUserExists('00000000-0000-0000-0000-000000000001', {
      authProvider: 'supabase',
      email: 'shantanu@example.com'
    });

    expect(query).toHaveBeenCalledTimes(1);
    const [, params] = query.mock.calls[0] as [string, unknown[]];
    expect(params[1]).toBe('shantanu@example.com');
    expect(params[2]).toBe('supabase');
  });

  test('synthesizes <userId>@<provider>.local when email missing', async () => {
    const query = vi.fn(async () => ({ rows: [] }));
    vi.doMock('../src/db.js', () => ({ pool: { query } }));
    const { ensureUserExists } = await import('../src/services/userService.js');

    await ensureUserExists('11111111-1111-1111-1111-111111111111');
    // No identity -> provider defaults 'dev', email synthesizes to '<userId>@dev.local'
    const [, params] = query.mock.calls[0] as [string, unknown[]];
    expect(params[1]).toBe('11111111-1111-1111-1111-111111111111@dev.local');
    expect(params[2]).toBe('dev');
  });

  test('SQL contains self-healing CASE for synthetic emails', async () => {
    // Regression test for V3.1 Phase 0: when an existing row has a
    // '@dev.local' email and a new call supplies a real email, the UPSERT
    // must overwrite. We assert the SQL string contains the CASE clause.
    const query = vi.fn(async () => ({ rows: [] }));
    vi.doMock('../src/db.js', () => ({ pool: { query } }));
    const { ensureUserExists } = await import('../src/services/userService.js');

    await ensureUserExists('22222222-2222-2222-2222-222222222222', {
      authProvider: 'supabase',
      email: 'real@example.com'
    });

    const [sql] = query.mock.calls[0] as [string, unknown[]];
    // Must heal synthetic emails
    expect(sql).toMatch(/users\.email\s+LIKE\s+'%@dev\.local'/);
    expect(sql).toMatch(/EXCLUDED\.email\s+NOT\s+LIKE\s+'%@dev\.local'/);
    // Must still preserve real emails via COALESCE in the ELSE branch
    expect(sql).toMatch(/COALESCE\(NULLIF\(users\.email,\s*''\)/);
    // Must still upgrade provider dev -> supabase
    expect(sql).toMatch(/users\.auth_provider\s*=\s*'dev'/);
  });

  test('treats whitespace and case in email defensively', async () => {
    const query = vi.fn(async () => ({ rows: [] }));
    vi.doMock('../src/db.js', () => ({ pool: { query } }));
    const { ensureUserExists } = await import('../src/services/userService.js');

    await ensureUserExists('33333333-3333-3333-3333-333333333333', {
      authProvider: 'SUPABASE',
      email: '  Shantanu@Example.com  '
    });
    const [, params] = query.mock.calls[0] as [string, unknown[]];
    expect(params[1]).toBe('shantanu@example.com');
    expect(params[2]).toBe('supabase');
  });
});
