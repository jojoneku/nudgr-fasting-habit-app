-- Migration 054 — server-authoritative sync timestamps (Phase 5)
--
-- ⚠️  DO NOT APPLY YET. This migration belongs to Phase 5 of
--     docs/sync_conflict_resolution_spec.md and must ship TOGETHER with the
--     client change that reads/writes `client_edited_at`. Phases 1–4 (the
--     conflict guard, ordered sync cycles, zone-scoped dirty marking) need no
--     migration and are already live without it.
--
-- Why it must not be applied alone
-- --------------------------------
-- Today every client supplies `updated_at` itself, so last-write-wins is
-- arbitrated by whichever device's wall clock wrote last. The trigger below
-- moves that stamp to the database clock — an improvement only once the client
-- also has a column carrying the *edit* time to order by. Applied on its own it
-- merely swaps one mixed-clock comparison for another: a device whose clock runs
-- fast would still win conflicts it should lose, and one running slow would
-- abandon its own fresh edits.
--
-- What Phase 5 changes
-- --------------------
--   `updated_at`       — server clock. Change detection / pull watermarks.
--                        Monotonic across devices, so it can be compared safely.
--   `client_edited_at` — originating device's edit time. The LWW ordering key.
--                        Nullable: legacy rows fall back to `updated_at`.

-- ── 1. Edit-time column (additive, backward compatible) ──────────────────────
ALTER TABLE user_profile      ADD COLUMN IF NOT EXISTS client_edited_at TIMESTAMPTZ;
ALTER TABLE user_collections  ADD COLUMN IF NOT EXISTS client_edited_at TIMESTAMPTZ;
ALTER TABLE nutrition_logs    ADD COLUMN IF NOT EXISTS client_edited_at TIMESTAMPTZ;
ALTER TABLE activity_logs     ADD COLUMN IF NOT EXISTS client_edited_at TIMESTAMPTZ;
ALTER TABLE finance_records   ADD COLUMN IF NOT EXISTS client_edited_at TIMESTAMPTZ;
ALTER TABLE fasting_state     ADD COLUMN IF NOT EXISTS client_edited_at TIMESTAMPTZ;
ALTER TABLE user_quests       ADD COLUMN IF NOT EXISTS client_edited_at TIMESTAMPTZ;
ALTER TABLE advisor_state     ADD COLUMN IF NOT EXISTS client_edited_at TIMESTAMPTZ;

-- ── 2. Server-authoritative updated_at ───────────────────────────────────────
-- Overrides whatever the client sent, so the column becomes a single monotonic
-- reference clock rather than a mix of eight devices' wall clocks.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_updated_at ON user_profile;
CREATE TRIGGER set_updated_at BEFORE INSERT OR UPDATE ON user_profile
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at ON user_collections;
CREATE TRIGGER set_updated_at BEFORE INSERT OR UPDATE ON user_collections
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at ON nutrition_logs;
CREATE TRIGGER set_updated_at BEFORE INSERT OR UPDATE ON nutrition_logs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at ON activity_logs;
CREATE TRIGGER set_updated_at BEFORE INSERT OR UPDATE ON activity_logs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at ON finance_records;
CREATE TRIGGER set_updated_at BEFORE INSERT OR UPDATE ON finance_records
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at ON fasting_state;
CREATE TRIGGER set_updated_at BEFORE INSERT OR UPDATE ON fasting_state
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at ON user_quests;
CREATE TRIGGER set_updated_at BEFORE INSERT OR UPDATE ON user_quests
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at ON advisor_state;
CREATE TRIGGER set_updated_at BEFORE INSERT OR UPDATE ON advisor_state
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── Rollback ─────────────────────────────────────────────────────────────────
-- DROP TRIGGER IF EXISTS set_updated_at ON <each table above>;
-- DROP FUNCTION IF EXISTS set_updated_at();
-- The client_edited_at columns are additive and safe to leave in place.
