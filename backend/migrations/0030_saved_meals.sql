-- Saved meals and collections
-- Date: 2026-05-16

CREATE TABLE IF NOT EXISTS saved_meal_collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, name)
);

CREATE TABLE IF NOT EXISTS saved_meals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    collection_id UUID NOT NULL REFERENCES saved_meal_collections(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    raw_text TEXT NOT NULL,
    input_kind TEXT,
    total_calories NUMERIC(10,2) NOT NULL CHECK (total_calories >= 0),
    total_protein_g NUMERIC(10,2) NOT NULL CHECK (total_protein_g >= 0),
    total_carbs_g NUMERIC(10,2) NOT NULL CHECK (total_carbs_g >= 0),
    total_fat_g NUMERIC(10,2) NOT NULL CHECK (total_fat_g >= 0),
    meal_payload_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_saved_meal_collections_user_updated
    ON saved_meal_collections(user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_saved_meals_user_updated
    ON saved_meals(user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_saved_meals_collection_updated
    ON saved_meals(collection_id, updated_at DESC);

ALTER TABLE saved_meal_collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_meals ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'saved_meal_collections'
      AND policyname = 'saved_meal_collections_user_isolation'
  ) THEN
    CREATE POLICY saved_meal_collections_user_isolation
      ON saved_meal_collections
      FOR ALL
      USING (
        current_user = 'postgres'
        OR user_id::text = current_setting('request.jwt.claim.sub', true)
      )
      WITH CHECK (
        current_user = 'postgres'
        OR user_id::text = current_setting('request.jwt.claim.sub', true)
      );
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'saved_meals'
      AND policyname = 'saved_meals_user_isolation'
  ) THEN
    CREATE POLICY saved_meals_user_isolation
      ON saved_meals
      FOR ALL
      USING (
        current_user = 'postgres'
        OR user_id::text = current_setting('request.jwt.claim.sub', true)
      )
      WITH CHECK (
        current_user = 'postgres'
        OR user_id::text = current_setting('request.jwt.claim.sub', true)
      );
  END IF;
END
$$;
