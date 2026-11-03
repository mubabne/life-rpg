-- AI quest generation: several batches per period, an AI-generation action for
-- signed-in users, and a server-only snapshot for the Gmail-to-quests pipeline.

alter table public.generation_runs drop constraint generation_runs_user_id_period_type_period_start_key;
alter table public.generation_runs add constraint generation_runs_period_payload_key unique (user_id, period_type, period_start, payload_hash);

create or replace function private.import_batch(owner_id uuid, batch jsonb, channel text) returns jsonb
language plpgsql set search_path = '' as $$
declare p public.profiles; period text; start_d date; end_d date; q jsonb; run public.generation_runs; result_id uuid; q_count integer; budget integer; w record;
begin
  select * into strict p from public.profiles where user_id=owner_id;
  if jsonb_typeof(batch) is distinct from 'object' or not(batch ?& array['schema_version','period_type','period_start','timezone','quests']) or batch-array['schema_version','period_type','period_start','timezone','quests'] <> '{}'::jsonb then raise exception 'Batch fields do not match schema version 1.'; end if;
  if batch->'schema_version' <> '1'::jsonb or jsonb_typeof(batch->'quests') <> 'array' then raise exception 'Use schema_version 1 and a quests array.'; end if;
  period := batch->>'period_type';
  if period not in ('weekly','monthly') or jsonb_typeof(batch->'period_type') <> 'string' then raise exception 'period_type must be weekly or monthly.'; end if;
  if jsonb_typeof(batch->'timezone') is distinct from 'string' or batch->>'timezone' is distinct from p.timezone then raise exception 'The batch time zone must match your profile: %',p.timezone; end if;
  if coalesce(batch->>'period_start','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'period_start must be YYYY-MM-DD.'; end if;
  start_d := (batch->>'period_start')::date;
  if period='weekly' and extract(isodow from start_d)<>1 or period='monthly' and extract(day from start_d)<>1 then raise exception 'Weekly periods start Monday; monthly periods start on the first.'; end if;
  end_d := case when period='weekly' then start_d+7 else (start_d+interval '1 month')::date end;
  if start_d < (now() at time zone p.timezone)::date-62 or start_d > (now() at time zone p.timezone)::date+62 then raise exception 'Import a period within 62 days of today.'; end if;
  q_count := jsonb_array_length(batch->'quests');
  if q_count not between 1 and 40 then raise exception 'A batch must contain 1–40 quests.'; end if;
  for q in select value from jsonb_array_elements(batch->'quests') loop
    if jsonb_typeof(q)<>'object' or not(q ?& array['item_key','title','description','stat_tag','cadence','difficulty','estimated_minutes','due_local_date']) or q-array['item_key','title','description','stat_tag','cadence','difficulty','estimated_minutes','due_local_date'] <> '{}'::jsonb then raise exception 'Quest fields do not match schema version 1.'; end if;
    if jsonb_typeof(q->'item_key')<>'string' or coalesce(q->>'item_key','') !~ '^[a-z0-9][a-z0-9_-]{0,63}$' then raise exception 'Each item_key needs 1–64 lowercase letters, numbers, underscores or hyphens.'; end if;
    if jsonb_typeof(q->'title')<>'string' or length(trim(q->>'title')) not between 1 and 120 or jsonb_typeof(q->'description')<>'string' or length(q->>'description')>2000 then raise exception 'Quest titles need 1–120 characters; descriptions allow up to 2000.'; end if;
    if q->>'stat_tag' not in ('health','mind','craft','social','wealth') or jsonb_typeof(q->'stat_tag')<>'string' then raise exception 'Choose a supported stat_tag.'; end if;
    if period='weekly' and q->>'cadence' not in ('daily','weekly') or period='monthly' and q->>'cadence'<>'monthly' or jsonb_typeof(q->'cadence')<>'string' then raise exception 'Weekly batches contain daily/weekly quests; monthly batches contain monthly quests.'; end if;
    if jsonb_typeof(q->'difficulty')<>'number' or q->>'difficulty' !~ '^[1-3]$' then raise exception 'Difficulty must be the integer 1, 2, or 3.'; end if;
    if jsonb_typeof(q->'estimated_minutes')<>'number' or q->>'estimated_minutes' !~ '^[0-9]{1,3}$' or (q->>'estimated_minutes')::integer not between 1 and 480 then raise exception 'estimated_minutes must be an integer from 1 to 480.'; end if;
    if jsonb_typeof(q->'due_local_date')<>'string' or q->>'due_local_date' !~ '^\d{4}-\d{2}-\d{2}$' or (q->>'due_local_date')::date<start_d or (q->>'due_local_date')::date>=end_d then raise exception 'Quest due dates must fall within the batch period.'; end if;
  end loop;
  if (select count(distinct value->>'item_key') from jsonb_array_elements(batch->'quests'))<>q_count then raise exception 'Each item_key must be unique within its batch.'; end if;
  -- Re-sending the same batch is a no-op; a different batch for the same period is added
  -- on top, still bounded by the shared weekly workload cap below.
  select * into run from public.generation_runs where user_id=owner_id and period_type=period and period_start=start_d and payload_hash=md5(batch::text);
  if found then return jsonb_build_object('run_id',run.id,'duplicate',true,'count',q_count); end if;
  budget := least(p.weekly_capacity,(private.review(owner_id)->>'next_capacity')::integer);
  for w in select date_trunc('week',(value->>'due_local_date')::date)::date as week_start,sum((value->>'estimated_minutes')::integer) as minutes from jsonb_array_elements(batch->'quests') group by 1 loop
    if w.minutes+coalesce((select sum(estimated_minutes) from public.quests where user_id=owner_id and source='ai' and due_local_date>=w.week_start and due_local_date<w.week_start+7),0)>budget then raise exception 'This batch exceeds your flexible workload cap of % minutes in the week of %. Include monthly work in that budget.',budget,w.week_start; end if;
  end loop;
  insert into public.generation_runs(user_id,period_type,period_start,timezone,schema_version,payload_hash,generator) values(owner_id,period,start_d,p.timezone,1,md5(batch::text),case channel when 'app' then 'openai' when 'gmail' then 'gmail' else 'chatgpt' end) returning id into result_id;
  for q in select value from jsonb_array_elements(batch->'quests') loop perform private.create_quest(owner_id,q,'ai',channel,null,result_id); end loop;
  return jsonb_build_object('run_id',result_id,'duplicate',false,'count',q_count);
end $$;

-- Signed-in users import AI batches through this wrapper, so they are recorded as app/openai.
create function private.import_ai(batch jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := auth.uid();
begin
  if owner_id is null then raise exception 'Sign in to continue.' using errcode='42501'; end if;
  perform private.ensure_user(owner_id);
  perform 1 from public.character_progress where user_id=owner_id for update;
  return private.import_batch(owner_id,batch,'app');
end $$;
create function public.life_rpg_import_ai(batch jsonb) returns jsonb
language sql security invoker set search_path = '' as $$ select private.import_ai(batch); $$;

-- The Gmail pipeline needs the owner's context (time zone, review, workload) to plan quests.
create function private.owner_snapshot(owner_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Server access only.' using errcode='42501'; end if;
  perform private.ensure_user(owner_id);
  perform 1 from public.character_progress where user_id=owner_id for update;
  perform private.materialize(owner_id);
  perform private.finalize_habits(owner_id);
  return private.snapshot(owner_id);
end $$;
create function public.life_rpg_owner_snapshot(owner_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select private.owner_snapshot(owner_id); $$;

revoke all on function private.import_batch(uuid,jsonb,text) from public,anon,authenticated,service_role;
revoke all on function private.import_ai(jsonb) from public,anon,authenticated,service_role;
revoke all on function private.owner_snapshot(uuid) from public,anon,authenticated,service_role;
grant execute on function private.import_ai(jsonb) to authenticated;
grant execute on function private.owner_snapshot(uuid) to service_role;
revoke all on function public.life_rpg_import_ai(jsonb) from public,anon,service_role;
grant execute on function public.life_rpg_import_ai(jsonb) to authenticated;
revoke all on function public.life_rpg_owner_snapshot(uuid) from public,anon,authenticated;
grant execute on function public.life_rpg_owner_snapshot(uuid) to service_role;
