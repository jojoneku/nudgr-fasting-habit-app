-- Migration 057 — refuse finance writes from outdated app builds (Plan 062 A)
--
-- Safe to apply, in either order relative to the client release:
--   * Applied before the client → no row carries a data_version yet, so the
--     guard below never fires. Older clients keep syncing exactly as before.
--   * Client before this is applied → the client probes for `data_version`,
--     finds no column, and omits it. Nothing changes until this is applied.
-- Writing a column PostgREST doesn't know about rejects the whole request, which
-- is why the client probes rather than assuming (same as migration 054).
--
-- What this fixes
-- ---------------
-- A build of the app reads a finance record into its model and writes it back
-- from that model. A build older than a field drops that field on the way. On
-- 2026-10-07 a browser tab left open across an update read six ShopeePay
-- installment purchases and wrote them back without `isInstallment`, which
-- stopped the plans being billed and halved the statement.
--
-- Last-write-wins could not catch it: the stale tab made a FRESH edit, with a
-- current timestamp, so it won. What it lacked was not recency but knowledge
-- of the data. `data_version` records which version of the finance data model
-- wrote each row (the client's `kFinanceDataVersion`), and the trigger refuses
-- to let a lower version overwrite a higher one.
--
-- Behaviour
-- ---------
--   * A row written by version N can only be overwritten by version N or
--     higher. A client that sends no version counts as 0 — every build from
--     before this migration — so it can never overwrite a row a current build
--     wrote.
--   * The refused update is SKIPPED, not raised: the trigger returns NULL, the
--     row stays as it was, and the rest of a batch upsert goes through. The
--     client sees the row missing from the upsert's RETURNING echo and treats
--     it as a lost conflict: it drops the push and takes the cloud copy on
--     its next pull.
--   * Inserts of new rows are never refused.
--   * Rows written before this migration have no version and stay writable by
--     anyone until a current build writes them once.

-- ── 1. Version column (additive, backward compatible) ────────────────────────
ALTER TABLE finance_records ADD COLUMN IF NOT EXISTS data_version INTEGER;

-- ── 2. The guard ─────────────────────────────────────────────────────────────
-- search_path is pinned, as in migration 054, so nothing resolves through a
-- caller-controlled schema.
CREATE OR REPLACE FUNCTION finance_records_guard_data_version()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF COALESCE(NEW.data_version, 0) < COALESCE(OLD.data_version, 0) THEN
    -- An outdated client: keep the row a newer build wrote.
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$;

-- BEFORE UPDATE triggers fire in name order, so this runs before
-- `set_updated_at` (migration 054); returning NULL stops that one too, which
-- keeps the skipped row's updated_at unchanged.
DROP TRIGGER IF EXISTS guard_data_version ON finance_records;
CREATE TRIGGER guard_data_version BEFORE UPDATE ON finance_records
  FOR EACH ROW EXECUTE FUNCTION finance_records_guard_data_version();

-- ── Rollback ─────────────────────────────────────────────────────────────────
-- DROP TRIGGER IF EXISTS guard_data_version ON finance_records;
-- DROP FUNCTION IF EXISTS finance_records_guard_data_version();
-- (Leave the column; the client stops sending it only if it is dropped.)
