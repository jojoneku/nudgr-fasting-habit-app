-- =============================================================================
-- Nudgr — Supabase Migration
-- Change: ai-financial-advisor  (SyncDomain.advisorState)
-- Run this once in the Supabase SQL editor for your project.
-- =============================================================================

-- ── advisor_state (one row per user) ─────────────────────────────────────────
-- Stores the financial advisor's synced state as a single LWW document:
--   data = { "history": [ {AiChatMessage}... ], "profile": {AdvisorProfile} }
-- Mirrors user_profile: one row per user, last-write-wins on updated_at.
CREATE TABLE IF NOT EXISTS advisor_state (
  user_id     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  data        JSONB NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT ALL ON public.advisor_state TO authenticated;

ALTER TABLE advisor_state ENABLE ROW LEVEL SECURITY;

-- User-scoped access only (same policy shape as every other sync table).
CREATE POLICY "user_owns_row" ON advisor_state
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
