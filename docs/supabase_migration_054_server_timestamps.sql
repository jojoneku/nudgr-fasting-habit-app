-- Migration 054 — server-authoritative sync timestamps (Phase 5)
--
-- Safe to apply, in either order relative to the client release:
--   * Applied without the client → the client probes for `client_edited_at`,
--     finds it, and starts using it. Nothing to coordinate.
--   * Client without this applied → the probe finds no column, the client omits
--     it, and conflict ordering falls back to `updated_at` exactly as before.
-- Writing a column PostgREST doesn't know about rejects the whole request, which
-- is why the client probes rather than assuming. See docs/sync_conflict_resolution_spec.md.
--
-- What this gives you
-- -------------------
--   `updated_at`       — server clock, via the trigger below. One monotonic
--                        reference every device can measure itself against.
--   `client_edited_at` — the originating device's edit time, written already
--                        corrected into server frame. Nullable: rows written
--                        before this migration stay null and fall back to
--                        `updated_at`.
--
-- Why both are needed. Last-write-wins has to order *edits*, and an edit time
-- can only be measured on the device that made it — the edit may happen offline,
-- hours before any server sees it. So the trigger alone does not remove clock
-- skew; it supplies the reference clock, and the client cancels its own drift
-- against it before writing `client_edited_at`. Applying this without the
-- Phase 5 client is harmless but buys nothing on its own.

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
-- search_path is pinned so an unqualified name can't be resolved through a
-- caller-controlled schema (Supabase's linter flags a mutable search_path).
-- now() is schema-qualified because an empty search_path leaves nothing
-- implicit.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

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
