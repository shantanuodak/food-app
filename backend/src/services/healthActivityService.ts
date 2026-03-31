import { pool } from '../db.js';

type ActivitySnapshot = {
  date: string;
  steps: number;
  activeEnergyKcal: number;
};

export async function upsertActivitySnapshot(
  userId: string,
  date: string,
  steps: number,
  activeEnergyKcal: number
): Promise<ActivitySnapshot> {
  const result = await pool.query<{ date: string; steps: string; active_energy_kcal: string }>(
    `
    INSERT INTO health_activity_snapshots (user_id, date, steps, active_energy_kcal, updated_at)
    VALUES ($1, $2, $3, $4, NOW())
    ON CONFLICT (user_id, date)
    DO UPDATE SET steps = $3, active_energy_kcal = $4, updated_at = NOW()
    RETURNING date, steps, active_energy_kcal
    `,
    [userId, date, steps, activeEnergyKcal]
  );

  const row = result.rows[0]!;
  return {
    date: row.date,
    steps: Number(row.steps),
    activeEnergyKcal: Number(row.active_energy_kcal),
  };
}

export async function getActivitySnapshot(
  userId: string,
  date: string
): Promise<ActivitySnapshot | null> {
  const result = await pool.query<{ date: string; steps: string; active_energy_kcal: string }>(
    `
    SELECT date, steps, active_energy_kcal
    FROM health_activity_snapshots
    WHERE user_id = $1 AND date = $2
    `,
    [userId, date]
  );

  const row = result.rows[0];
  if (!row) return null;

  return {
    date: row.date,
    steps: Number(row.steps),
    activeEnergyKcal: Number(row.active_energy_kcal),
  };
}
