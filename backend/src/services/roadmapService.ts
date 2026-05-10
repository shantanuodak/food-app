import { pool } from '../db.js';

export type RoadmapItemType = 'fix' | 'feature';
export type RoadmapStatus = 'not_started' | 'in_progress' | 'done';

export type RoadmapItemInput = {
  itemType: RoadmapItemType;
  title: string;
  description: string;
  status: RoadmapStatus;
  releaseVersion: string | null;
  targetDate: string | null;
  targetDateLabel: string;
  displayOrder: number;
  isVisible: boolean;
  sourceFeedbackId: string | null;
};

export type RoadmapItemRow = RoadmapItemInput & {
  id: string;
  createdAt: string;
  updatedAt: string;
  sourceFeedback?: {
    id: string;
    feedbackType: string;
    userEmail: string | null;
    message: string;
    createdAt: string;
  } | null;
};

type DbRoadmapRow = {
  id: string;
  item_type: RoadmapItemType;
  title: string;
  description: string;
  status: RoadmapStatus;
  release_version: string | null;
  target_date: string | Date | null;
  target_date_label: string;
  display_order: number;
  is_visible: boolean;
  source_feedback_id: string | null;
  created_at: Date;
  updated_at: Date;
  feedback_type?: string | null;
  feedback_user_email?: string | null;
  feedback_message?: string | null;
  feedback_created_at?: Date | null;
};

function dateOnly(value: string | Date | null): string | null {
  if (!value) return null;
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return value.slice(0, 10);
}

function mapRow(row: DbRoadmapRow): RoadmapItemRow {
  return {
    id: row.id,
    itemType: row.item_type,
    title: row.title,
    description: row.description,
    status: row.status,
    releaseVersion: row.release_version,
    targetDate: dateOnly(row.target_date),
    targetDateLabel: row.target_date_label,
    displayOrder: row.display_order,
    isVisible: row.is_visible,
    sourceFeedbackId: row.source_feedback_id,
    createdAt: row.created_at.toISOString(),
    updatedAt: row.updated_at.toISOString(),
    sourceFeedback: row.source_feedback_id
      ? {
          id: row.source_feedback_id,
          feedbackType: row.feedback_type || 'general',
          userEmail: row.feedback_user_email || null,
          message: row.feedback_message || '',
          createdAt: row.feedback_created_at ? row.feedback_created_at.toISOString() : ''
        }
      : null
  };
}

const roadmapSelect = `
  SELECT
    r.id, r.item_type, r.title, r.description, r.status,
    r.release_version, r.target_date, r.target_date_label,
    r.display_order, r.is_visible, r.source_feedback_id,
    r.created_at, r.updated_at,
    f.feedback_type, f.user_email AS feedback_user_email,
    f.message AS feedback_message, f.created_at AS feedback_created_at
  FROM public_roadmap_items r
  LEFT JOIN user_feedback f ON f.id = r.source_feedback_id
`;

export async function listRoadmapItems(opts: { visibleOnly?: boolean } = {}): Promise<RoadmapItemRow[]> {
  const result = await pool.query<DbRoadmapRow>(
    `
    ${roadmapSelect}
    ${opts.visibleOnly ? 'WHERE r.is_visible = TRUE' : ''}
    ORDER BY r.item_type, r.display_order ASC, r.created_at DESC
    `
  );
  return result.rows.map(mapRow);
}

export async function createRoadmapItem(input: RoadmapItemInput): Promise<RoadmapItemRow> {
  const result = await pool.query<DbRoadmapRow>(
    `
    INSERT INTO public_roadmap_items (
      item_type, title, description, status, release_version,
      target_date, target_date_label, display_order, is_visible, source_feedback_id
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
    RETURNING id, item_type, title, description, status, release_version,
              target_date, target_date_label, display_order, is_visible,
              source_feedback_id, created_at, updated_at
    `,
    [
      input.itemType,
      input.title,
      input.description,
      input.status,
      input.releaseVersion,
      input.targetDate,
      input.targetDateLabel || 'TBD',
      input.displayOrder,
      input.isVisible,
      input.sourceFeedbackId
    ]
  );

  return (await getRoadmapItem(result.rows[0]!.id))!;
}

export async function updateRoadmapItem(id: string, input: RoadmapItemInput): Promise<RoadmapItemRow | null> {
  const result = await pool.query<{ id: string }>(
    `
    UPDATE public_roadmap_items
    SET item_type = $2,
        title = $3,
        description = $4,
        status = $5,
        release_version = $6,
        target_date = $7,
        target_date_label = $8,
        display_order = $9,
        is_visible = $10,
        source_feedback_id = $11,
        updated_at = NOW()
    WHERE id = $1
    RETURNING id
    `,
    [
      id,
      input.itemType,
      input.title,
      input.description,
      input.status,
      input.releaseVersion,
      input.targetDate,
      input.targetDateLabel || 'TBD',
      input.displayOrder,
      input.isVisible,
      input.sourceFeedbackId
    ]
  );
  if ((result.rowCount || 0) === 0) return null;
  return getRoadmapItem(id);
}

export async function reorderRoadmapItems(itemType: RoadmapItemType, ids: string[]): Promise<RoadmapItemRow[]> {
  const uniqueIds = Array.from(new Set(ids));
  if (uniqueIds.length !== ids.length) {
    throw new Error('Roadmap reorder ids must be unique');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const existing = await client.query<{ id: string }>(
      `
      SELECT id
      FROM public_roadmap_items
      WHERE item_type = $1 AND id = ANY($2::uuid[])
      FOR UPDATE
      `,
      [itemType, ids]
    );

    if (existing.rowCount !== ids.length) {
      throw new Error('Roadmap reorder contains unknown or mismatched items');
    }

    for (let index = 0; index < ids.length; index += 1) {
      await client.query(
        `
        UPDATE public_roadmap_items
        SET display_order = $3,
            updated_at = NOW()
        WHERE item_type = $1 AND id = $2
        `,
        [itemType, ids[index], index]
      );
    }

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }

  return listRoadmapItems();
}

export async function getRoadmapItem(id: string): Promise<RoadmapItemRow | null> {
  const result = await pool.query<DbRoadmapRow>(
    `
    ${roadmapSelect}
    WHERE r.id = $1
    `,
    [id]
  );
  return result.rows[0] ? mapRow(result.rows[0]) : null;
}

export function groupRoadmapItems(items: RoadmapItemRow[]): { fixes: RoadmapItemRow[]; features: RoadmapItemRow[] } {
  return {
    fixes: items.filter((item) => item.itemType === 'fix'),
    features: items.filter((item) => item.itemType === 'feature')
  };
}
