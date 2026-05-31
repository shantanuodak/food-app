import { timingSafeEqual } from 'node:crypto';

/**
 * Constant-time comparison of a submitted secret against the expected value.
 *
 * Returns false for missing/empty values or length mismatches, and otherwise
 * compares in constant time. Avoids the timing side-channel of `===`/`!==`,
 * which can let an attacker brute-force a shared admin key one byte at a time.
 */
export function timingSafeKeyEqual(
  submitted: string | undefined | null,
  expected: string | undefined | null
): boolean {
  if (!submitted || !expected) return false;
  const submittedBuf = Buffer.from(submitted);
  const expectedBuf = Buffer.from(expected);
  if (submittedBuf.length !== expectedBuf.length) return false;
  return timingSafeEqual(submittedBuf, expectedBuf);
}
