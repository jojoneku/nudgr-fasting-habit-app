-- Migration 055 — enable Realtime change events on the synced tables
--
-- Safe to apply at any time, in either order relative to the client release:
--   * Applied without the client → events are published, nobody subscribes.
--   * Client without this applied → subscribe() succeeds, no events arrive, and
--     the app falls back to its boot / resume / manual sync triggers.
-- Nothing about sync correctness depends on it. See docs/realtime_sync_spec.md.
--
-- What this does
-- --------------
-- Adds the eight synced tables to the `supabase_realtime` publication so
-- Postgres streams their changes over logical replication to the Realtime
-- server, which fans them out to subscribed clients.
--
-- Access control is unchanged: Realtime enforces the existing `user_owns_row`
-- RLS policies per subscriber using the caller's JWT, and the client also sets
-- a server-side `user_id=eq.<uid>` filter. A user can only ever receive their
-- own rows. Note this does mean row data — including finance records — now
-- flows through the Realtime server as well as PostgREST.

-- ── 1. Publish changes for the synced tables ─────────────────────────────────
-- Idempotent: ALTER PUBLICATION ... ADD TABLE errors if the table is already a
-- member, so each is guarded.
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'user_profile',
    'user_collections',
    'nutrition_logs',
    'activity_logs',
    'finance_records',
    'fasting_state',
    'user_quests',
    'advisor_state'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;

-- ── 2. Replica identity ──────────────────────────────────────────────────────
-- DEFAULT publishes only the primary key for UPDATE/DELETE old-row images.
-- Every table here has a natural PK covering user_id, which is exactly what the
-- client's `user_id=eq.<uid>` filter needs to match on a DELETE — so DEFAULT is
-- sufficient and FULL would only add replication volume for payloads the client
-- discards anyway (events are a trigger, not a delivery).
--
-- Left explicit so the reasoning survives: if a future change makes the client
-- read event payloads, this is the line to revisit.
--   ALTER TABLE public.finance_records REPLICA IDENTITY FULL;

-- ── Rollback ─────────────────────────────────────────────────────────────────
-- ALTER PUBLICATION supabase_realtime DROP TABLE public.user_profile;
-- ...repeat per table. Clients degrade to resume/boot sync automatically.
