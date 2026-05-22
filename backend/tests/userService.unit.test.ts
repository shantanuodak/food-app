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

  test('passes display_name through and trims/caps it', async () => {
    const query = vi.fn(async () => ({ rows: [] }));
    vi.doMock('../src/db.js', () => ({ pool: { query } }));
    const { ensureUserExists } = await import('../src/services/userService.js');

    await ensureUserExists('44444444-4444-4444-4444-444444444444', {
      authProvider: 'supabase',
      email: 'tanmay@example.com',
      displayName: '   Tanmay Roy   '
    });

    const [sql, params] = query.mock.calls[0] as [string, unknown[]];
    expect(params[4]).toBe('Tanmay Roy');
    // SQL must use COALESCE(NULLIF(...)) so the UPSERT cannot wipe a
    // previously-set name with a NULL/empty incoming value.
    expect(sql).toMatch(/display_name\s*=\s*COALESCE\(NULLIF\(users\.display_name,\s*''\),\s*EXCLUDED\.display_name\)/);
  });

  test('display_name treats empty/whitespace as NULL on upsert', async () => {
    const query = vi.fn(async () => ({ rows: [] }));
    vi.doMock('../src/db.js', () => ({ pool: { query } }));
    const { ensureUserExists } = await import('../src/services/userService.js');

    await ensureUserExists('55555555-5555-5555-5555-555555555555', {
      authProvider: 'supabase',
      email: 'tanmay@example.com',
      displayName: '   '
    });
    const [, params] = query.mock.calls[0] as [string, unknown[]];
    expect(params[4]).toBeNull();
  });

  test('display_name omitted entirely is NULL', async () => {
    const query = vi.fn(async () => ({ rows: [] }));
    vi.doMock('../src/db.js', () => ({ pool: { query } }));
    const { ensureUserExists } = await import('../src/services/userService.js');

    await ensureUserExists('66666666-6666-6666-6666-666666666666', {
      authProvider: 'supabase',
      email: 'tanmay@example.com'
    });
    const [, params] = query.mock.calls[0] as [string, unknown[]];
    expect(params[4]).toBeNull();
  });

  test('display_name is capped at 80 chars', async () => {
    const query = vi.fn(async () => ({ rows: [] }));
    vi.doMock('../src/db.js', () => ({ pool: { query } }));
    const { ensureUserExists } = await import('../src/services/userService.js');

    const longName = 'x'.repeat(120);
    await ensureUserExists('77777777-7777-7777-7777-777777777777', {
      authProvider: 'supabase',
      email: 'long@example.com',
      displayName: longName
    });
    const [, params] = query.mock.calls[0] as [string, unknown[]];
    expect((params[4] as string).length).toBe(80);
  });
});

describe('userService.updateUserDisplayName', () => {
  beforeEach(() => {
    vi.resetModules();
  });
  afterEach(() => {
    vi.resetModules();
  });

  test('trims, caps to 80 chars, and persists', async () => {
    const query = vi.fn(async () => ({ rows: [] }));
    vi.doMock('../src/db.js', () => ({ pool: { query } }));
    const { updateUserDisplayName } = await import('../src/services/userService.js');

    const persisted = await updateUserDisplayName(
      '88888888-8888-8888-8888-888888888888',
      '   Tanmay Roy   '
    );
    expect(persisted).toBe('Tanmay Roy');
    const [sql, params] = query.mock.calls[0] as [string, unknown[]];
    expect(sql).toMatch(/UPDATE users/);
    expect(sql).toMatch(/SET display_name = \$2/);
    expect(params[0]).toBe('88888888-8888-8888-8888-888888888888');
    expect(params[1]).toBe('Tanmay Roy');
  });

  test('writes NULL when the trimmed value is empty (clears the field)', async () => {
    const query = vi.fn(async () => ({ rows: [] }));
    vi.doMock('../src/db.js', () => ({ pool: { query } }));
    const { updateUserDisplayName } = await import('../src/services/userService.js');

    const persisted = await updateUserDisplayName(
      '99999999-9999-9999-9999-999999999999',
      '    '
    );
    expect(persisted).toBeNull();
    const [, params] = query.mock.calls[0] as [string, unknown[]];
    expect(params[1]).toBeNull();
  });

  test('caps overlong input at 80 chars', async () => {
    const query = vi.fn(async () => ({ rows: [] }));
    vi.doMock('../src/db.js', () => ({ pool: { query } }));
    const { updateUserDisplayName } = await import('../src/services/userService.js');

    const persisted = await updateUserDisplayName(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'a'.repeat(200)
    );
    expect(persisted?.length).toBe(80);
  });
});

describe('userService.getUserDisplayName', () => {
  beforeEach(() => {
    vi.resetModules();
  });
  afterEach(() => {
    vi.resetModules();
  });

  test('returns the trimmed name when row exists', async () => {
    const query = vi.fn(async () => ({ rows: [{ display_name: '  Tanmay  ' }] }));
    vi.doMock('../src/db.js', () => ({ pool: { query } }));
    const { getUserDisplayName } = await import('../src/services/userService.js');

    const value = await getUserDisplayName('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
    expect(value).toBe('Tanmay');
  });

  test('returns null when the row is missing', async () => {
    const query = vi.fn(async () => ({ rows: [] }));
    vi.doMock('../src/db.js', () => ({ pool: { query } }));
    const { getUserDisplayName } = await import('../src/services/userService.js');

    const value = await getUserDisplayName('cccccccc-cccc-cccc-cccc-cccccccccccc');
    expect(value).toBeNull();
  });

  test('returns null when the column is empty/whitespace', async () => {
    const query = vi.fn(async () => ({ rows: [{ display_name: '   ' }] }));
    vi.doMock('../src/db.js', () => ({ pool: { query } }));
    const { getUserDisplayName } = await import('../src/services/userService.js');

    const value = await getUserDisplayName('dddddddd-dddd-dddd-dddd-dddddddddddd');
    expect(value).toBeNull();
  });
});
