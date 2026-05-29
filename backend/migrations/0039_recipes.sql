-- Recipe imports and saved recipes
-- Date: 2026-05-28

CREATE TABLE IF NOT EXISTS recipe_imports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_url TEXT NOT NULL,
    source_domain TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'saved', 'failed')),
    draft_json JSONB,
    error_code TEXT,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS recipes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    import_id UUID REFERENCES recipe_imports(id) ON DELETE SET NULL,
    title TEXT NOT NULL CHECK (length(trim(title)) > 0),
    source_url TEXT NOT NULL,
    source_domain TEXT NOT NULL,
    source_name TEXT,
    hero_image_url TEXT,
    description TEXT,
    servings TEXT,
    prep_time TEXT,
    cook_time TEXT,
    total_time TEXT,
    categories TEXT[] NOT NULL DEFAULT '{}',
    cuisines TEXT[] NOT NULL DEFAULT '{}',
    keywords TEXT[] NOT NULL DEFAULT '{}',
    nutrition_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS recipe_ingredients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK (position >= 0),
    raw_text TEXT NOT NULL CHECK (length(trim(raw_text)) > 0),
    quantity_text TEXT,
    unit_text TEXT,
    ingredient_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (recipe_id, position)
);

CREATE TABLE IF NOT EXISTS recipe_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK (position >= 0),
    text TEXT NOT NULL CHECK (length(trim(text)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (recipe_id, position)
);

CREATE INDEX IF NOT EXISTS idx_recipe_imports_user_created
    ON recipe_imports(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_recipes_user_updated
    ON recipes(user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_recipes_source_domain
    ON recipes(source_domain);

CREATE INDEX IF NOT EXISTS idx_recipe_ingredients_recipe_position
    ON recipe_ingredients(recipe_id, position);

CREATE INDEX IF NOT EXISTS idx_recipe_steps_recipe_position
    ON recipe_steps(recipe_id, position);

ALTER TABLE recipe_imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE recipe_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE recipe_steps ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL PRIVILEGES ON TABLE recipe_imports, recipes, recipe_ingredients, recipe_steps FROM anon;
    REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM anon;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL PRIVILEGES ON TABLE recipe_imports, recipes, recipe_ingredients, recipe_steps FROM authenticated;
    REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM authenticated;
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'recipe_imports'
      AND policyname = 'recipe_imports_user_isolation'
  ) THEN
    CREATE POLICY recipe_imports_user_isolation
      ON recipe_imports
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
      AND tablename = 'recipes'
      AND policyname = 'recipes_user_isolation'
  ) THEN
    CREATE POLICY recipes_user_isolation
      ON recipes
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
      AND tablename = 'recipe_ingredients'
      AND policyname = 'recipe_ingredients_user_isolation'
  ) THEN
    CREATE POLICY recipe_ingredients_user_isolation
      ON recipe_ingredients
      FOR ALL
      USING (
        current_user = 'postgres'
        OR EXISTS (
          SELECT 1
          FROM recipes r
          WHERE r.id = recipe_ingredients.recipe_id
            AND r.user_id::text = current_setting('request.jwt.claim.sub', true)
        )
      )
      WITH CHECK (
        current_user = 'postgres'
        OR EXISTS (
          SELECT 1
          FROM recipes r
          WHERE r.id = recipe_ingredients.recipe_id
            AND r.user_id::text = current_setting('request.jwt.claim.sub', true)
        )
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
      AND tablename = 'recipe_steps'
      AND policyname = 'recipe_steps_user_isolation'
  ) THEN
    CREATE POLICY recipe_steps_user_isolation
      ON recipe_steps
      FOR ALL
      USING (
        current_user = 'postgres'
        OR EXISTS (
          SELECT 1
          FROM recipes r
          WHERE r.id = recipe_steps.recipe_id
            AND r.user_id::text = current_setting('request.jwt.claim.sub', true)
        )
      )
      WITH CHECK (
        current_user = 'postgres'
        OR EXISTS (
          SELECT 1
          FROM recipes r
          WHERE r.id = recipe_steps.recipe_id
            AND r.user_id::text = current_setting('request.jwt.claim.sub', true)
        )
      );
  END IF;
END
$$;
