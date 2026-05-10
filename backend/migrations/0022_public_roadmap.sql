-- Public roadmap CMS. Admins curate feedback into visible fixes/features;
-- app users only see items marked visible.

ALTER TABLE user_feedback
  ADD COLUMN IF NOT EXISTS feedback_type TEXT NOT NULL DEFAULT 'general'
  CHECK (feedback_type IN ('general', 'bug', 'feature'));

CREATE TABLE IF NOT EXISTS public_roadmap_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_type TEXT NOT NULL CHECK (item_type IN ('fix', 'feature')),
    title TEXT NOT NULL CHECK (length(title) >= 1 AND length(title) <= 160),
    description TEXT NOT NULL DEFAULT '' CHECK (length(description) <= 1200),
    status TEXT NOT NULL DEFAULT 'not_started'
      CHECK (status IN ('not_started', 'in_progress', 'done')),
    release_version TEXT CHECK (release_version IS NULL OR length(release_version) <= 40),
    target_date DATE,
    target_date_label TEXT NOT NULL DEFAULT 'TBD' CHECK (length(target_date_label) <= 40),
    display_order INTEGER NOT NULL DEFAULT 0,
    is_visible BOOLEAN NOT NULL DEFAULT TRUE,
    source_feedback_id UUID REFERENCES user_feedback(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_public_roadmap_visible_type_order
    ON public_roadmap_items(is_visible, item_type, display_order, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_public_roadmap_feedback
    ON public_roadmap_items(source_feedback_id)
    WHERE source_feedback_id IS NOT NULL;
