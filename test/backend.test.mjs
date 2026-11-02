import {test, before, after} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';

const db = new PGlite();
const alice='00000000-0000-4000-8000-000000000001';
const bob='00000000-0000-4000-8000-000000000002';
before(async()=>{
  await db.exec(`create schema auth;
    create role anon; create role authenticated; create role service_role bypassrls;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object('role',current_setting('request.jwt.claim.role',true))$$;
    grant usage on schema auth to authenticated,anon,service_role;
    grant execute on all functions in schema auth to authenticated,anon,service_role;`);
  await db.exec(readFileSync(new URL('../supabase/migrations/20261102103605_life_rpg_core.sql',import.meta.url),'utf8'));
  await db.query('insert into auth.users values ($1),($2)',[alice,bob]);
});
after(()=>db.close());
async function asUser(user, fn) {
  await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)",[user]);
  await db.exec('set role authenticated');
  try{return await fn();}finally{await db.exec('reset role');}
}
async function act(action,args={},user=alice){return asUser(user,async()=> (await db.query('select public.life_rpg($1,$2::jsonb) as result',[action,JSON.stringify(args)])).rows[0].result);}
const quest=(extra={})=>({title:'Read ten pages',description:'A little wiser.',stat_tag:'mind',cadence:'daily',difficulty:2,estimated_minutes:15,due_local_date:today,...extra});
let today;
test('bootstrap, RLS isolation, and direct writes are denied',async()=>{
  const snap=await act('snapshot'); today=snap.today;
  assert.equal(snap.progress.total_xp,0); assert.equal(Object.keys(snap.stats).length,5);
  await asUser(alice,async()=>{
    assert.equal((await db.query('select * from public.profiles')).rows.length,1);
    await assert.rejects(db.query('update public.character_progress set total_xp=999'),/permission denied/);
    await assert.rejects(db.query("select private.award($1,'fake','mind',999,999)",[alice]),/permission denied/);
  });
});
test('completion replay grants one reward and prevents foreign ownership access',async()=>{
  const {id}=await act('create_quest',quest());
  await assert.rejects(act('complete_quest',{id},bob),/Quest not found/);
  await Promise.all([act('complete_quest',{id}),act('complete_quest',{id})]);
  const snap=await act('snapshot');
  assert.equal(snap.progress.total_xp,40); assert.equal(snap.progress.gold,10);
  assert.equal(snap.stats.mind,40);
  assert.equal((await db.query('select count(*)::int n from public.reward_ledger where quest_id=$1',[id])).rows[0].n,1);
});
test('quest reward fields from clients cannot change the server reward',async()=>{
  const {id}=await act('create_quest',quest({difficulty:1,xp_reward:9999,gold_reward:9999}));
  await act('complete_quest',{id});
  assert.equal((await act('snapshot')).progress.total_xp,60);
});
test('habit check-ins are idempotent; missing days consume two freezes then decay',async()=>{
  const {id}=await act('create_habit',{title:'Water',stat_tag:'health'});
  await act('checkin_habit',{id}); await act('checkin_habit',{id});
  const snap=await act('snapshot');
  assert.equal(snap.progress.total_xp,65); assert.equal(snap.habits[0].streak,1);
  // Twelve missed days guarantee decay even across a monthly allowance reset.
  await db.query("update public.habits set start_date=$2::date-12,last_evaluated=$2::date-13,strength=.8,streak=10 where id=$1",[id,today]);
  await db.query('delete from public.habit_days where habit_id=$1 and local_date<>$2::date',[id,today]);
  await act('snapshot');
  const days=(await db.query('select outcome from public.habit_days where habit_id=$1 and local_date<$2::date order by local_date',[id,today])).rows;
  assert.equal(days.length,12);
  const frozen=days.filter(d=>d.outcome==='frozen').length;
  assert.ok(frozen>=2 && frozen<=4);
  const habit=(await db.query('select strength,streak from public.habits where id=$1',[id])).rows[0];
  assert.ok(Math.abs(Number(habit.strength)-.8*Math.pow(.9,12-frozen))<1e-8);
  assert.equal(habit.streak,0);
  await act('snapshot');
  assert.equal((await db.query('select count(*)::int n from public.habit_days where habit_id=$1',[id])).rows[0].n,13);
});
function batch(extra={}){
  const date=new Date(`${today}T00:00:00Z`);const weekday=(date.getUTCDay()+6)%7;date.setUTCDate(date.getUTCDate()-weekday);
  return {schema_version:1,period_type:'weekly',period_start:date.toISOString().slice(0,10),timezone:'Asia/Ulaanbaatar',quests:[quest({item_key:'read-pages',difficulty:1})],...extra};
}
test('batch replays deduplicate across transports and failures roll back',async()=>{
  const b=batch();const first=await act('import_batch',{batch:b});const again=await act('import_batch',{batch:b});
  assert.equal(first.run_id,again.run_id);assert.equal(again.duplicate,true);
  await assert.rejects(act('import_batch',{batch:{...b,quests:[{...b.quests[0],title:'Different'}]}}),/different batch/);
  await assert.rejects(act('import_batch',{batch:{...b,quests:[{...b.quests[0],xp_reward:9000}]}}),/fields/);
  await assert.rejects(act('import_batch',{batch:{...b,quests:[b.quests[0],b.quests[0]]}}),/unique/);
  assert.equal((await db.query('select count(*)::int n from public.generation_runs where user_id=$1',[alice])).rows[0].n,1);
});
test('all batch properties must be non-null and valid JSON types',async()=>{
  for (const key of ['schema_version','period_type','period_start','timezone','quests']) {
    await assert.rejects(act('import_batch',{batch:{...batch(),[key]:null}}),`null ${key} must be rejected`);
  }
  for(const key of ['item_key','title','description','stat_tag','cadence','difficulty','estimated_minutes','due_local_date']) {
    const b=batch();b.quests[0][key]=null;
    await assert.rejects(act('import_batch',{batch:b}),`null quest ${key} must be rejected`);
  }
});
test('recurring generation is repeatable and creates concrete occurrences',async()=>{
  const {id}=await act('create_template',quest({cadence:'daily'}));
  await act('snapshot');await act('snapshot');
  assert.equal((await db.query('select count(*)::int n from public.quests where template_id=$1',[id])).rows[0].n,1);
});
test('level boundaries use cumulative growth curve on the server',async()=>{
  for(const [xp,level] of [[0,1],[99,1],[100,2],[382,2],[383,3]]) {
    await db.query('update public.character_progress set total_xp=$2 where user_id=$1',[bob,xp]);
    assert.equal((await act('snapshot',{},bob)).progress.level,level);
  }
});
test('month-end recurrence clamps February and shorter months',async()=>{
  const year=Number(today.slice(0,4))-1;
  const result=await db.query("insert into public.quest_templates(user_id,title,description,stat_tag,cadence,difficulty,estimated_minutes,start_date) values($1,'Monthly check','','wealth','monthly',1,10,$2) returning id",[bob,`${year}-01-31`]);
  await act('snapshot',{},bob);
  const dates=(await db.query("select due_local_date::text d from public.quests where template_id=$1",[result.rows[0].id])).rows.map(r=>r.d);
  assert.ok(dates.includes(`${year}-02-28`)||dates.includes(`${year}-02-29`));
  assert.ok(dates.includes(`${year}-04-30`));
});
test('server ingestion requires service role and acknowledges duplicate messages',async()=>{
  await asUser(alice,async()=>{await assert.rejects(db.query('select public.life_rpg_ingest($1,$2,$3,$4::jsonb)',[alice,'mail','msg',JSON.stringify(batch())]),/permission denied/);});
  await db.exec("select set_config('request.jwt.claim.role','service_role',false); set role service_role");
  try {
    const a=(await db.query('select public.life_rpg_ingest($1,$2,$3,$4::jsonb) result',[alice,'mail','msg',JSON.stringify(batch())])).rows[0].result;
    const b=(await db.query('select public.life_rpg_ingest($1,$2,$3,$4::jsonb) result',[alice,'mail','msg',JSON.stringify(batch())])).rows[0].result;
    assert.equal(a.run_id,b.run_id);assert.equal(b.duplicate,true);
  } finally {await db.exec('reset role');}
});
