// Supabase Edge Function — returns the HuggingFace read token to authenticated
// app users. The token is configured as a function secret (`HF_TOKEN`) and is
// never bundled into the APK.
//
// Deploy:
//   supabase functions deploy get-hf-token
//   supabase secrets set HF_TOKEN=hf_xxx
//
// Behavior:
//   - Requires a valid Supabase auth JWT in the Authorization header.
//     supabase-js attaches this automatically when the user is signed in.
//   - Returns { token } on success.
//   - 401 if unauthenticated, 500 if HF_TOKEN secret is missing.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const hfToken = Deno.env.get('HF_TOKEN');

  if (!supabaseUrl || !supabaseAnonKey) {
    return json({ error: 'server_misconfigured' }, 500);
  }
  if (!hfToken) {
    return json({ error: 'hf_token_not_set' }, 500);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return json({ error: 'unauthenticated' }, 401);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) {
    return json({ error: 'unauthenticated' }, 401);
  }

  return json({ token: hfToken }, 200);
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
