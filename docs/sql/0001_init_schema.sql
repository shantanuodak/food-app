-- Food App MVP initial schema
-- Date: 2026-02-15

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL UNIQUE,
    auth_provider TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS onboarding_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    goal TEXT NOT NULL,
    diet_preference TEXT NOT NULL,
    allergies_json JSONB NOT NULL DEFAULT '[]'::jsonb,
    units TEXT NOT NULL CHECK (units IN ('metric', 'imperial')),
    activity_level TEXT NOT NULL,
    calorie_target INTEGER NOT NULL CHECK (calorie_target > 0),
    macro_target_protein NUMERIC(8,2) NOT NULL CHECK (macro_target_protein >= 0),
    macro_target_carbs NUMERIC(8,2) NOT NULL CHECK (macro_target_carbs >= 0),
    macro_target_fat NUMERIC(8,2) NOT NULL CHECK (macro_target_fat >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS food_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    logged_at TIMESTAMPTZ NOT NULL,
    meal_type TEXT,
    raw_text TEXT NOT NULL,
    total_calories NUMERIC(10,2) NOT NULL CHECK (total_calories >= 0),
    total_protein_g NUMERIC(10,2) NOT NULL CHECK (total_protein_g >= 0),
    total_carbs_g NUMERIC(10,2) NOT NULL CHECK (total_carbs_g >= 0),
    total_fat_g NUMERIC(10,2) NOT NULL CHECK (total_fat_g >= 0),
    parse_confidence NUMERIC(4,3) NOT NULL CHECK (parse_confidence >= 0 AND parse_confidence <= 1),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS food_log_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    food_log_id UUID NOT NULL REFERENCES food_logs(id) ON DELETE CASCADE,
    food_name TEXT NOT NULL,
    quantity NUMERIC(10,3) NOT NULL CHECK (quantity >= 0),
    unit TEXT NOT NULL,
    grams NUMERIC(10,3) NOT NULL CHECK (grams >= 0),
    calories NUMERIC(10,2) NOT NULL CHECK (calories >= 0),
    protein_g NUMERIC(10,2) NOT NULL CHECK (protein_g >= 0),
    carbs_g NUMERIC(10,2) NOT NULL CHECK (carbs_g >= 0),
    fat_g NUMERIC(10,2) NOT NULL CHECK (fat_g >= 0),
    nutrition_source_id TEXT NOT NULL,
    match_confidence NUMERIC(4,3) NOT NULL CHECK (match_confidence >= 0 AND match_confidence <= 1)
);

CREATE TABLE IF NOT EXISTS parse_cache (
    text_hash TEXT PRIMARY KEY,
    normalized_json JSONB NOT NULL,
    confidence NUMERIC(4,3) NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hit_count BIGINT NOT NULL DEFAULT 0 CHECK (hit_count >= 0)
);

CREATE TABLE IF NOT EXISTS ai_cost_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    request_id TEXT NOT NULL,
    feature TEXT NOT NULL CHECK (feature IN ('parse_fallback', 'escalation', 'enrichment')),
    model TEXT NOT NULL,
    input_tokens INTEGER NOT NULL CHECK (input_tokens >= 0),
    output_tokens INTEGER NOT NULL CHECK (output_tokens >= 0),
    estimated_cost_usd NUMERIC(12,6) NOT NULL CHECK (estimated_cost_usd >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_food_logs_user_logged_at ON food_logs(user_id, logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_food_log_items_food_log_id ON food_log_items(food_log_id);
CREATE INDEX IF NOT EXISTS idx_parse_cache_last_used_at ON parse_cache(last_used_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_cost_events_created_at ON ai_cost_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_cost_events_user_created_at ON ai_cost_events(user_id, created_at DESC);

