-- =============================================================================
-- Nudgr — Supabase Migration 058
-- Change: add-app-lock  (openspec/changes/add-app-lock)
-- Run this once in the Supabase SQL editor for your project.
-- =============================================================================
--
-- Safe to apply before or after the client release:
--   * Applied without the client → an empty table nobody reads.
--   * Client without this applied → AppLockRemote sees a missing table and the
--     app hides the Security controls. Nothing else breaks.
--
-- NOT a SyncDomain. The client reads and writes this row directly (write-through,
-- online only) so a PIN can never be clobbered by an offline last-write-wins
-- push of some other blob. See design.md decision 3.

-- ── app_lock (one row per user) ──────────────────────────────────────────────
-- verifier = { "v": 1, "algo": "pbkdf2-sha256", "iterations": N,
--              "salt": "<base64>", "hash": "<base64>", "length": 4|6 }
-- It is a salted PBKDF2 hash. The PIN itself is never sent or stored.
--
-- verifier IS NULL means "no PIN — app lock off". Turning the lock off writes
-- NULL instead of deleting the row: an UPDATE is delivered to filtered Realtime
-- subscribers, a DELETE is not.
CREATE TABLE IF NOT EXISTS app_lock (
  user_id     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  verifier    JSONB,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT ALL ON public.app_lock TO authenticated;

ALTER TABLE app_lock ENABLE ROW LEVEL SECURITY;

-- User-scoped access only (same policy shape as every other user table).
DROP POLICY IF EXISTS "user_owns_row" ON app_lock;
CREATE POLICY "user_owns_row" ON app_lock
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── Realtime ─────────────────────────────────────────────────────────────────
-- Lets other signed-in devices pick up a PIN change at once. Best-effort: the
-- client also re-reads the row on sign-in and on every foreground / tab show.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'app_lock'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.app_lock;
  END IF;
END $$;
