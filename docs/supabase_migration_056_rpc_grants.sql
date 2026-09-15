-- Migration 056 — lock down the AI rate-limit RPC.
--
-- Why: Supabase's own database linter flagged
-- `anon_security_definer_function_executable` on public.increment_ai_usage.
-- Migration 001 granted EXECUTE to `authenticated`, but PostgreSQL ALSO grants
-- EXECUTE on every new function to PUBLIC by default, and that default was
-- never revoked — so the RPC was callable unauthenticated at
-- /rest/v1/rpc/increment_ai_usage with nothing but the public anon key.
--
-- It was not exploitable: auth.uid() is NULL for anon, so the INSERT died on
-- the NOT NULL user_id constraint (verified live, 23502). Nothing was written
-- and nothing leaked. But an unauthenticated caller reaching a SECURITY
-- DEFINER body at all is the wrong default, and the error it produced was
-- indistinguishable from a real bug.
--
-- Safe to re-run. Reversible with:
--   GRANT EXECUTE ON FUNCTION public.increment_ai_usage() TO anon;

-- 1. Drop the implicit PUBLIC grant, and anon explicitly in case it was ever
--    granted directly. `authenticated` is re-granted below, after the rewrite.
REVOKE EXECUTE ON FUNCTION public.increment_ai_usage() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.increment_ai_usage() FROM anon;

-- 2. Rewrite the body with two hardening changes and no behaviour change for
--    a signed-in caller:
--
--    * `SET search_path = ''` instead of `= public`. A SECURITY DEFINER
--      function runs as the table owner, so anything it resolves through a
--      mutable search_path is a privilege-escalation path — a caller who can
--      create objects in an earlier schema (pg_temp is searched first by
--      default) could shadow a name this body relies on. Empty search_path
--      plus fully-qualified names removes the question entirely.
--
--    * An explicit NULL-subject guard. Belt and suspenders with the REVOKE
--      above: if the function is ever re-granted by accident, it now refuses
--      an anonymous caller with a readable message instead of a NOT NULL
--      violation that reads like a schema bug.
CREATE OR REPLACE FUNCTION public.increment_ai_usage()
  RETURNS INT
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = ''
AS $$
DECLARE
  new_count INT;
  caller    UUID := auth.uid();
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'increment_ai_usage requires an authenticated caller'
      USING ERRCODE = '28000';
  END IF;

  -- The INSERT target is schema-qualified because that name IS resolved
  -- through search_path. The two references below are NOT: inside ON CONFLICT
  -- DO UPDATE and RETURNING, `ai_coach_rate_limit` is a range variable bound to
  -- the target table, so it resolves without search_path and schema-qualifying
  -- it there would not parse.
  INSERT INTO public.ai_coach_rate_limit AS rl (user_id, day, count)
  VALUES (caller, CURRENT_DATE, 1)
  ON CONFLICT (user_id, day) DO UPDATE
    SET count = rl.count + 1
  RETURNING rl.count INTO new_count;

  RETURN new_count;
END;
$$;

-- 3. CREATE OR REPLACE resets the grant list to the default, which includes
--    PUBLIC again. Revoke it a second time, then re-grant only the one role
--    that should ever call this. Order matters: do not reorder these.
REVOKE EXECUTE ON FUNCTION public.increment_ai_usage() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.increment_ai_usage() FROM anon;
GRANT  EXECUTE ON FUNCTION public.increment_ai_usage() TO authenticated;

-- 4. Document the deny-all RLS on the counter table so it stops reading like
--    an oversight. The linter reports `rls_enabled_no_policy` on it at INFO
--    level; that is the intended state. RLS on with zero policies denies every
--    client role outright, and the SECURITY DEFINER function above runs as the
--    table owner, which bypasses RLS. Adding a policy would only widen access.
COMMENT ON TABLE public.ai_coach_rate_limit IS
  'Per-user daily Bedrock call counter. RLS is enabled with NO policies on '
  'purpose: no client role may touch this table directly. All access goes '
  'through the SECURITY DEFINER function public.increment_ai_usage(), which '
  'runs as the owner and derives the user from auth.uid(). Do not add a policy.';
