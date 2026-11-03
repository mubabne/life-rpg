// Signed-in users call this from the app to have GPT plan their week.
// It reads the player's snapshot and imports the batch as that same user,
// so the database's own validation, ownership and workload rules still apply.
import {ContractError} from '../_shared/quest-contract.mjs';
import {planQuests} from '../_shared/ai-planner.mjs';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {status, headers: {...cors, 'Content-Type': 'application/json'}});

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', {headers: cors});
  if (request.method !== 'POST') return json({error: 'Use POST.'}, 405);
  const auth = request.headers.get('Authorization') ?? '';
  const apikey = request.headers.get('apikey') ?? Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  if (!auth.startsWith('Bearer ')) return json({error: 'Sign in to generate quests.'}, 401);

  async function rpc(name: string, params: unknown) {
    const response = await fetch(`${Deno.env.get('SUPABASE_URL')}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json', apikey, Authorization: auth},
      body: JSON.stringify(params),
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok) throw new ContractError(result.message ?? 'Could not reach your adventure.');
    return result;
  }

  try {
    let input: {week?: string; focus?: string} = {};
    try { input = await request.json(); } catch { /* empty body is fine */ }
    const week = ['current', 'next', 'auto'].includes(input.week ?? '') ? input.week : 'auto';
    const focus = typeof input.focus === 'string' ? input.focus.slice(0, 500) : '';
    const snapshot = await rpc('life_rpg', {action: 'snapshot', args: {}});
    const plan = await planQuests({
      snapshot, week, focus,
      apiKey: Deno.env.get('OPENAI_API_KEY'),
      model: Deno.env.get('OPENAI_MODEL') || undefined,
    });
    if (!plan.batch) return json({ok: false, error: plan.reason}, 422);
    const receipt = await rpc('life_rpg_import_ai', {batch: plan.batch});
    return json({
      ok: true,
      count: plan.batch.quests.length,
      period_start: plan.window.periodStart,
      titles: plan.batch.quests.map((q: {title: string}) => q.title),
      receipt,
    });
  } catch (error) {
    const reason = error instanceof ContractError ? error.message : 'Quest generation is temporarily unavailable. Try again later.';
    if (!(error instanceof ContractError)) console.error(error);
    return json({ok: false, error: reason}, error instanceof ContractError ? 422 : 503);
  }
});
