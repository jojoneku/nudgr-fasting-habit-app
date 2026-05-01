-- =============================================================================
-- The System — Supabase Migration
-- Plan: 015-full-cloud-sync
-- Run this once in the Supabase SQL editor for your project.
-- =============================================================================

-- ── user_profile (one row per user) ──────────────────────────────────────────
-- Stores: fasting state, user stats, goals, streaks, settings
CREATE TABLE IF NOT EXISTS user_profile (
  user_id     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  data        JSONB NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── user_collections (one row per user) ──────────────────────────────────────
-- Stores: quests[], achievements[], routines[], food_library[]
CREATE TABLE IF NOT EXISTS user_collections (
  user_id     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  data        JSONB NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── nutrition_logs (one row per user per date) ────────────────────────────────
-- Stores: DailyNutritionLog + chat messages for that date
CREATE TABLE IF NOT EXISTS nutrition_logs (
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date        TEXT NOT NULL,  -- 'yyyy-MM-dd'
  data        JSONB NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, date)
);

-- ── activity_logs (one row per user per date) ─────────────────────────────────
CREATE TABLE IF NOT EXISTS activity_logs (
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date        TEXT NOT NULL,  -- 'yyyy-MM-dd'
  data        JSONB NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, date)
);

-- ── finance_records (one row per user per record) ─────────────────────────────
-- Single table for all 9 finance collections — discriminated by `table_name`
CREATE TABLE IF NOT EXISTS finance_records (
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  table_name  TEXT NOT NULL,
  record_id   TEXT NOT NULL,
  data        JSONB NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, table_name, record_id)
);

-- =============================================================================
-- Grant access to authenticated users
-- =============================================================================

GRANT ALL ON public.user_profile     TO authenticated;
GRANT ALL ON public.user_collections TO authenticated;
GRANT ALL ON public.nutrition_logs   TO authenticated;
GRANT ALL ON public.activity_logs    TO authenticated;
GRANT ALL ON public.finance_records  TO authenticated;

-- =============================================================================
-- Row Level Security — each user can only access their own rows
-- =============================================================================

ALTER TABLE user_profile       ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_collections   ENABLE ROW LEVEL SECURITY;
ALTER TABLE nutrition_logs     ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_logs      ENABLE ROW LEVEL SECURITY;
ALTER TABLE finance_records    ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_owns_row" ON user_profile
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_owns_row" ON user_collections
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_owns_row" ON nutrition_logs
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_owns_row" ON activity_logs
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_owns_row" ON finance_records
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- =============================================================================
-- Indexes for common query patterns
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_nutrition_logs_user_date
  ON nutrition_logs (user_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_activity_logs_user_date
  ON activity_logs (user_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_finance_records_user_table
  ON finance_records (user_id, table_name);
