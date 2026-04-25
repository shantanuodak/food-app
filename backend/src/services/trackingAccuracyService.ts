import { pool } from '../db.js';

type LowConfidenceEntry = {
  rawText: string;
  confidence: number;
  loggedAt: string;
  suggestion: string;
};

type TrackingAccuracySummary = {
  period: string;
  entryCount: number;
  averageConfidence: number;
  tier: 'excellent' | 'good' | 'fair' | 'needs_work';
  lowConfidenceEntries: LowConfidenceEntry[];
};

function round3(value: number): number {
  return Math.round(value * 1000) / 1000;
}

function tierFromConfidence(avg: number): TrackingAccuracySummary['tier'] {
  if (avg >= 0.85) return 'excellent';
  if (avg >= 0.70) return 'good';
  if (avg >= 0.55) return 'fair';
  return 'needs_work';
}

/**
 * Generate a simple rule-based coaching suggestion for a low-confidence entry.
 * No AI call — just pattern matching on what's missing from the text.
 */
function generateSuggestion(rawText: string): string {
  const trimmed = rawText.trim();
  const words = trimmed.split(/\s+/);
  const hasNumber = /\d/.test(trimmed);
  const hasUnit = /\b(cups?|oz|tbsp|tsp|slices?|pieces?|grams?|g|ml|lbs?|servings?|bowl|plate|handful)\b/i.test(trimmed);

  if (words.length === 1) {
    return `Try being more specific — e.g. "grilled ${trimmed} breast 6oz"`;
  }
  if (!hasNumber && !hasUnit) {
    return `Try adding a quantity — e.g. "1 cup ${trimmed}" or "2 servings ${trimmed}"`;
  }
  if (hasNumber && !hasUnit) {
    return `Try adding a unit — e.g. "${trimmed} oz" or "${trimmed} cup"`;
  }
  return 'Try specifying the brand or preparation method for better accuracy';
}

export async function getTrackingAccuracy(
  userId: string,
  _date: string,
  _timezone: string
): Promise<TrackingAccuracySummary> {
  // Aggregate confidence across ALL of the user's food logs — no rolling
  // window. Older logs were previously excluded by a 7-day filter which
  // caused the card to appear empty for users whose recent week was quiet.
  const statsResult = await pool.query<{
    entry_count: string;
    avg_confidence: string | null;
  }>(
    `
    SELECT
      COUNT(*)::text AS entry_count,
      AVG(parse_confidence)::text AS avg_confidence
    FROM food_logs
    WHERE user_id = $1
    `,
    [userId]
  );

  const entryCount = parseInt(statsResult.rows[0]?.entry_count || '0', 10);
  const avgRaw = parseFloat(statsResult.rows[0]?.avg_confidence || '0');
  const averageConfidence = Number.isFinite(avgRaw) ? round3(avgRaw) : 0;

  if (entryCount === 0) {
    return {
      period: 'all',
      entryCount: 0,
      averageConfidence: 0,
      tier: 'needs_work',
      lowConfidenceEntries: []
    };
  }

  // Get the 3 lowest-confidence entries across all time for coaching
  const lowResult = await pool.query<{
    raw_text: string;
    parse_confidence: string;
    logged_at: string;
  }>(
    `
    SELECT raw_text, parse_confidence::text, logged_at::text
    FROM food_logs
    WHERE user_id = $1
      AND parse_confidence < 0.80
    ORDER BY parse_confidence ASC, logged_at DESC
    LIMIT 3
    `,
    [userId]
  );

  const lowConfidenceEntries: LowConfidenceEntry[] = lowResult.rows.map((row) => ({
    rawText: row.raw_text,
    confidence: round3(parseFloat(row.parse_confidence)),
    loggedAt: row.logged_at,
    suggestion: generateSuggestion(row.raw_text)
  }));

  return {
    period: 'all',
    entryCount,
    averageConfidence,
    tier: tierFromConfidence(averageConfidence),
    lowConfidenceEntries
  };
}
