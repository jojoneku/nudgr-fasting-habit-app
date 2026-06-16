-- =============================================================================
-- The System — Supabase Migration
-- Plan: 053 Phase 3.5 — Immutable cloud snapshots ("the backup that is never
-- deleted"). Run this ONCE in the Supabase SQL editor (DB migrations are manual).
--
-- Stores periodic full-state snapshots of a user's local data. The normal sync
-- code NEVER updates or deletes these rows (it only INSERTs new ones and prunes
-- the oldest beyond a retention cap), so even if live sync ever clobbers a
-- singleton row (the bug behind three rounds of data loss), an earlier snapshot
-- remains intact and restorable.
-- =============================================================================

-- ── backups (many rows per user; append-only + retention prune) ───────────────
CREATE TABLE IF NOT EXISTS backups (
  user_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  taken_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  data      JSONB NOT NULL,
  PRIMARY KEY (user_id, taken_at)
);

-- Fast "newest first" listing / prune for a user.
CREATE INDEX IF NOT EXISTS backups_user_taken_idx
  ON backups (user_id, taken_at DESC);

GRANT ALL ON public.backups TO authenticated;

ALTER TABLE backups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_owns_row" ON backups
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
