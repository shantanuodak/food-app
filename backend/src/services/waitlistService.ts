import { pool } from '../db.js';

export type WaitlistSignupInput = {
  email: string;
  source: string;
  userAgent: string | null;
};

export type WaitlistSignupRow = {
  id: string;
  email: string;
  source: string;
  createdAt: string;
  alreadyJoined: boolean;
};

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

export async function saveWaitlistSignup(input: WaitlistSignupInput): Promise<WaitlistSignupRow> {
  const email = input.email.trim();
  const emailNormalized = normalizeEmail(email);
  const source = input.source.trim() || 'website';

  const result = await pool.query<{
    id: string;
    email: string;
    source: string;
    created_at: Date;
    inserted: boolean;
  }>(
    `
    INSERT INTO waitlist_signups (email, email_normalized, source, user_agent)
    VALUES ($1, $2, $3, $4)
    ON CONFLICT (email_normalized) DO UPDATE
      SET updated_at = NOW()
    RETURNING id, email, source, created_at, (xmax = 0) AS inserted
    `,
    [email, emailNormalized, source, input.userAgent]
  );

  const row = result.rows[0]!;
  return {
    id: row.id,
    email: row.email,
    source: row.source,
    createdAt: row.created_at.toISOString(),
    alreadyJoined: !row.inserted
  };
}
