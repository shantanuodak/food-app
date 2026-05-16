-- Keep AI cost telemetry aligned with the image parser orchestrator.
-- The app route should never fail after a successful Gemini parse because a
-- new internal cost feature was not included in the database check constraint.

ALTER TABLE ai_cost_events
  DROP CONSTRAINT IF EXISTS ai_cost_events_feature_check;

ALTER TABLE ai_cost_events
  ADD CONSTRAINT ai_cost_events_feature_check
  CHECK (
    feature IN (
      'parse_fallback',
      'escalation',
      'enrichment',
      'parse_image_primary',
      'parse_image_fallback',
      'parse_image_caption',
      'parse_image_caption_text',
      'parse_image_inventory_v2'
    )
  );
