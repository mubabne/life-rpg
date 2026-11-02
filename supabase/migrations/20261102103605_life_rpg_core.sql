-- Life RPG: all game mutations are transactional and server authoritative.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Adventurer' check (length(trim(display_name)) between 1 and 60),
  timezone text not null default 'Asia/Ulaanbaatar',
  weekly_capacity integer not null default 120 check (weekly_capacity between 15 and 10080),
  created_at timestamptz not null default now()
);
create table public.character_progress (
  user_id uuid primary key references public.profiles(user_id) on delete cascade,
  total_xp bigint not null default 0 check (total_xp >= 0),
  gold bigint not null default 0 check (gold >= 0)
);
create table public.character_stats (
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  stat_tag text not null check (stat_tag in ('health','mind','craft','social','wealth')),
  stat_xp bigint not null default 0 check (stat_xp >= 0),
  primary key (user_id, stat_tag)
);
create table public.quest_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 120),
  description text not null default '' check (length(description) <= 2000),
  stat_tag text not null check (stat_tag in ('health','mind','craft','social','wealth')),
  cadence text not null check (cadence in ('daily','weekly','monthly')),
  difficulty integer not null check (difficulty between 1 and 3),
  estimated_minutes integer not null check (estimated_minutes between 1 and 480),
  start_date date not null,
  last_generated date,
  archived_at timestamptz,
  unique (user_id, id)
);
create table public.weekly_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  week_start date not null,
  cutoff_at timestamptz not null,
  summary jsonb not null,
  notes text not null default '' check (length(notes) <= 2000),
  unique (user_id, week_start),
  unique (user_id, id)
);
create table public.generation_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  period_type text not null check (period_type in ('weekly','monthly')),
  period_start date not null,
  timezone text not null,
  schema_version integer not null check (schema_version = 1),
  payload_hash text not null,
  generator text not null default 'chatgpt',
  created_at timestamptz not null default now(),
  unique (user_id, period_type, period_start),
  unique (user_id, id)
);
create table public.quests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  template_id uuid,
  generation_run_id uuid,
  item_key text,
  title text not null check (length(trim(title)) between 1 and 120),
  description text not null default '' check (length(description) <= 2000),
  stat_tag text not null check (stat_tag in ('health','mind','craft','social','wealth')),
  cadence text not null check (cadence in ('daily','weekly','monthly')),
  difficulty integer not null check (difficulty between 1 and 3),
  estimated_minutes integer not null check (estimated_minutes between 1 and 480),
  xp_reward integer not null check (xp_reward between 0 and 80),
  gold_reward integer not null check (gold_reward between 0 and 20),
  due_local_date date not null,
  due_timezone text not null,
  due_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','completed','skipped')),
  source text not null check (source in ('ai','email','manual')),
  transport text not null check (transport in ('gmail','paste','app','schedule')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  foreign key (user_id, template_id) references public.quest_templates(user_id,id),
  foreign key (user_id, generation_run_id) references public.generation_runs(user_id,id),
  unique (user_id, id),
  unique (template_id, due_local_date),
  unique (generation_run_id, item_key),
  check ((status = 'completed') = (completed_at is not null))
);
create index quests_board on public.quests(user_id,status,due_local_date);
create index quests_run on public.quests(user_id,generation_run_id);
create index quests_template on public.quests(user_id,template_id);
create table public.quest_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  quest_id uuid not null,
  event_type text not null check (event_type in ('completed','skipped')),
  reason text not null default '' check (length(reason) <= 500),
  created_at timestamptz not null default now(),
  foreign key (user_id,quest_id) references public.quests(user_id,id) on delete cascade
);
create index quest_events_owner on public.quest_events(user_id,quest_id,created_at);
create table public.habits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 120),
  stat_tag text not null check (stat_tag in ('health','mind','craft','social','wealth')),
  start_date date not null,
  last_evaluated date not null,
  strength numeric not null default 0 check (strength between 0 and 1),
  streak integer not null default 0 check (streak >= 0),
  archived_at timestamptz,
  unique (user_id,id)
);
create table public.habit_days (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  habit_id uuid not null,
  local_date date not null,
  timezone text not null,
  outcome text not null check (outcome in ('completed','missed','frozen')),
  created_at timestamptz not null default now(),
  foreign key (user_id,habit_id) references public.habits(user_id,id) on delete cascade,
  unique (habit_id,local_date),
  unique (user_id,id)
);
create index habit_days_owner on public.habit_days(user_id,local_date);
create index habit_days_habit on public.habit_days(user_id,habit_id);
create table public.reward_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  event_key text not null,
  quest_id uuid,
  habit_day_id uuid,
  xp_delta integer not null check (xp_delta >= 0),
  gold_delta integer not null check (gold_delta >= 0),
  stat_tag text not null check (stat_tag in ('health','mind','craft','social','wealth')),
  rule_version integer not null default 1,
  created_at timestamptz not null default now(),
  unique (user_id,event_key),
  foreign key (user_id,quest_id) references public.quests(user_id,id),
  foreign key (user_id,habit_day_id) references public.habit_days(user_id,id),
  check (num_nonnulls(quest_id,habit_day_id) = 1)
);
create index reward_ledger_quest on public.reward_ledger(user_id,quest_id);
create index reward_ledger_habit on public.reward_ledger(user_id,habit_day_id);
create table public.ingestion_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  mailbox text not null,
  gmail_message_id text not null,
  generation_run_id uuid,
  status text not null check (status in ('committed','rejected')),
  error text,
  created_at timestamptz not null default now(),
  foreign key (user_id,generation_run_id) references public.generation_runs(user_id,id),
  unique (user_id,mailbox,gmail_message_id)
);
create index ingestion_events_run on public.ingestion_events(user_id,generation_run_id);

-- Explicit grants: RLS restricts reads; mutations are granted only as RPCs.
do $$ declare t text; begin
  foreach t in array array['profiles','character_progress','character_stats','quest_templates','weekly_reviews','generation_runs','quests','quest_events','habits','habit_days','reward_ledger','ingestion_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create policy own_rows on public.%I for select to authenticated using ((select auth.uid()) = user_id)', t);
  end loop;
end $$;

create function private.ensure_user(owner_id uuid) returns void
language plpgsql set search_path = '' as $$
begin
  insert into public.profiles(user_id) values (owner_id) on conflict do nothing;
  insert into public.character_progress(user_id) values (owner_id) on conflict do nothing;
  insert into public.character_stats(user_id,stat_tag)
    select owner_id, unnest(array['health','mind','craft','social','wealth']) on conflict do nothing;
end $$;

create function private.on_user_created() returns trigger
language plpgsql security definer set search_path = '' as $$
begin perform private.ensure_user(new.id); return new; end $$;
create trigger life_rpg_user_created after insert on auth.users
for each row execute function private.on_user_created();

create function private.award(owner_id uuid, event text, stat text, xp integer, coins integer, quest uuid default null, habit_day uuid default null) returns void
language plpgsql set search_path = '' as $$
begin
  insert into public.reward_ledger(user_id,event_key,quest_id,habit_day_id,xp_delta,gold_delta,stat_tag)
  values(owner_id,event,quest,habit_day,xp,coins,stat) on conflict do nothing;
  if found then
    update public.character_progress set total_xp = total_xp + xp, gold = gold + coins where user_id = owner_id;
    update public.character_stats set stat_xp = stat_xp + xp where user_id = owner_id and stat_tag = stat;
  end if;
end $$;

create function private.create_quest(owner_id uuid, data jsonb, origin text default 'manual', channel text default 'app', template uuid default null, run uuid default null) returns uuid
language plpgsql set search_path = '' as $$
declare result uuid; tz text; due date; difficulty integer;
begin
  select timezone into strict tz from public.profiles where user_id = owner_id;
  due := (data->>'due_local_date')::date;
  difficulty := (data->>'difficulty')::integer;
  insert into public.quests(user_id,template_id,generation_run_id,item_key,title,description,stat_tag,cadence,difficulty,estimated_minutes,xp_reward,gold_reward,due_local_date,due_timezone,due_at,source,transport)
  values (owner_id,template,run,data->>'item_key',trim(data->>'title'),coalesce(data->>'description',''),data->>'stat_tag',data->>'cadence',difficulty,(data->>'estimated_minutes')::integer,
    (array[20,40,80])[difficulty],(array[5,10,20])[difficulty],due,tz,(due+1)::timestamp at time zone tz,origin,channel)
  on conflict do nothing returning id into result;
  return result;
end $$;

create function private.materialize(owner_id uuid) returns void
language plpgsql set search_path = '' as $$
declare t public.quest_templates; today date; ending date; d date; first_d date;
begin
  select (now() at time zone timezone)::date into today from public.profiles where user_id = owner_id;
  for t in select * from public.quest_templates where user_id = owner_id and archived_at is null for update loop
    ending := case t.cadence when 'daily' then today when 'weekly' then date_trunc('week',today)::date+6 else (date_trunc('month',today)+interval '1 month - 1 day')::date end;
    first_d := greatest(t.start_date,coalesce(t.last_generated+1,t.start_date));
    for d in select generate_series(first_d,ending,interval '1 day')::date loop
      if t.cadence = 'daily'
        or (t.cadence = 'weekly' and extract(isodow from d) = extract(isodow from t.start_date))
        or (t.cadence = 'monthly' and extract(day from d) = least(extract(day from t.start_date),extract(day from date_trunc('month',d)+interval '1 month - 1 day'))) then
        perform private.create_quest(owner_id,jsonb_build_object('title',t.title,'description',t.description,'stat_tag',t.stat_tag,'cadence',t.cadence,'difficulty',t.difficulty,'estimated_minutes',t.estimated_minutes,'due_local_date',d),'manual','schedule',t.id);
      end if;
    end loop;
    update public.quest_templates set last_generated = greatest(coalesce(last_generated,start_date-1),ending) where id = t.id;
  end loop;
end $$;

create function private.finalize_habits(owner_id uuid) returns void
language plpgsql set search_path = '' as $$
declare h public.habits; d date; today date; tz text; frozen integer; day_outcome text;
begin
  select timezone,(now() at time zone timezone)::date into tz,today from public.profiles where user_id = owner_id;
  for h in select * from public.habits where user_id = owner_id and archived_at is null for update loop
    for d in select generate_series(h.last_evaluated+1,today-1,interval '1 day')::date loop
      select count(*) into frozen from public.habit_days where habit_id = h.id and outcome = 'frozen' and local_date >= date_trunc('month',d)::date and local_date < (date_trunc('month',d)+interval '1 month')::date;
      day_outcome := case when frozen < 2 then 'frozen' else 'missed' end;
      insert into public.habit_days(user_id,habit_id,local_date,timezone,outcome) values(owner_id,h.id,d,tz,day_outcome) on conflict do nothing;
      if found then
        update public.habits set strength = case when day_outcome = 'missed' then strength * .9 else strength end, streak = case when day_outcome = 'missed' then 0 else streak end where id = h.id;
      end if;
    end loop;
    update public.habits set last_evaluated = greatest(last_evaluated,today-1) where id = h.id;
  end loop;
end $$;

create function private.progress(owner_id uuid) returns jsonb
language plpgsql stable set search_path = '' as $$
declare xp bigint; coins bigint; remaining bigint; level integer := 1; required bigint;
begin
  select total_xp,gold into xp,coins from public.character_progress where user_id = owner_id;
  remaining := xp; required := 100;
  while remaining >= required loop
    remaining := remaining-required; level := level+1; required := ceil(100*power(level::numeric,1.5))::bigint;
  end loop;
  return jsonb_build_object('total_xp',xp,'gold',coins,'level',level,'xp_into_level',remaining,'xp_to_next',required,'level_fraction',remaining::numeric/required);
end $$;

create function private.review(owner_id uuid) returns jsonb
language plpgsql set search_path = '' as $$
declare p public.profiles; start_d date; cutoff timestamptz; saved public.weekly_reviews; summary jsonb; done integer; skipped integer; total integer; cap integer; prior jsonb; details text; stat_results jsonb;
begin
  select * into p from public.profiles where user_id = owner_id;
  start_d := date_trunc('week',now() at time zone p.timezone)::date-7;
  cutoff := (start_d+7)::timestamp at time zone p.timezone;
  select * into saved from public.weekly_reviews where user_id = owner_id and week_start = start_d;
  if not found then
    select count(*),count(*) filter(where completed_at < cutoff),count(*) filter(where exists(select 1 from public.quest_events e where e.quest_id = q.id and e.event_type = 'skipped' and e.created_at < cutoff))
      into total,done,skipped from public.quests q where q.user_id = owner_id and due_local_date >= start_d and due_local_date < start_d+7 and created_at < cutoff;
    select r.summary into prior from public.weekly_reviews r where r.user_id = owner_id and r.week_start = start_d-7;
    cap := least(p.weekly_capacity,coalesce((prior->>'next_capacity')::integer,p.weekly_capacity));
    if total >= 3 and done::numeric/total < .5 then cap := greatest(15,floor(cap*.8)::integer);
    elsif total >= 3 and done::numeric/total >= .85 and (prior->>'total')::integer >= 3 and (prior->>'completion_rate')::numeric >= .85 then cap := least(p.weekly_capacity,ceil(cap*1.1)::integer); end if;
    select coalesce(string_agg(format('- [%s] %s (%s, %s min)%s',case when q.completed_at < cutoff then 'done' when exists(select 1 from public.quest_events e where e.quest_id=q.id and e.event_type='skipped' and e.created_at<cutoff) then 'skipped' else 'unfinished' end,q.title,q.stat_tag,q.estimated_minutes,coalesce((select ' — '||e.reason from public.quest_events e where e.quest_id=q.id and e.event_type='skipped' and e.created_at<cutoff order by e.created_at limit 1),'')),E'\n' order by q.due_local_date),'No quests were due this week.') into details from public.quests q where q.user_id = owner_id and q.due_local_date >= start_d and q.due_local_date < start_d+7 and q.created_at < cutoff;
    select coalesce(jsonb_object_agg(stat_tag,n),'{}'::jsonb) into stat_results from (select stat_tag,count(*) filter(where completed_at<cutoff) n from public.quests where user_id=owner_id and due_local_date>=start_d and due_local_date<start_d+7 and created_at<cutoff group by stat_tag) s;
    summary := jsonb_build_object('week_start',start_d,'completed',done,'skipped',skipped,'overdue',total-done-skipped,'total',total,'completion_rate',case when total=0 then 0 else done::numeric/total end,'next_capacity',cap,'by_stat',stat_results,
      'habit_completions',(select count(*) from public.habit_days where user_id=owner_id and local_date>=start_d and local_date<start_d+7 and outcome='completed'),
      'message',case when total=0 then 'Your story is just getting started. Pick a small first quest.' when total>=3 and done::numeric/total<.5 then 'Let’s make next week a little lighter. Keep your essentials and shrink the flexible quests.' when done::numeric/total>=.85 then 'You’re finding your rhythm. Keep the time budget steady and try a small challenge.' else 'Keep a steady pace. Small steps still move the story forward.' end,
      'export_text',format(E'Life RPG weekly review\nWeek: %s through %s\nCompleted: %s; skipped: %s; unfinished: %s\nNext flexible quest budget: %s minutes per week (including monthly quest work).\nTime zone: %s. Weeks start Monday.\n\n%s\n\nGenerate schema_version 1 quest JSON. Balance Health, Mind, Craft, Social, and Wealth. Preserve fixed responsibilities. Scale flexible quests to this budget. Never generate XP, gold, ownership, or status fields.',start_d,start_d+6,done,skipped,total-done-skipped,cap,p.timezone,details));
    insert into public.weekly_reviews(user_id,week_start,cutoff_at,summary) values(owner_id,start_d,cutoff,summary) on conflict do nothing;
    select * into saved from public.weekly_reviews where user_id=owner_id and week_start=start_d;
  end if;
  return saved.summary || jsonb_build_object('export_text',(saved.summary->>'export_text')||case when saved.notes<>'' then E'\n\nMy reflection: '||saved.notes else '' end,'notes',saved.notes);
end $$;

create function private.import_batch(owner_id uuid, batch jsonb, channel text) returns jsonb
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
  select * into run from public.generation_runs where user_id=owner_id and period_type=period and period_start=start_d;
  if found then
    if run.payload_hash<>md5(batch::text) then raise exception 'This period already has a different batch. It was not replaced.'; end if;
    return jsonb_build_object('run_id',run.id,'duplicate',true,'count',q_count);
  end if;
  budget := least(p.weekly_capacity,(private.review(owner_id)->>'next_capacity')::integer);
  for w in select date_trunc('week',(value->>'due_local_date')::date)::date as week_start,sum((value->>'estimated_minutes')::integer) as minutes from jsonb_array_elements(batch->'quests') group by 1 loop
    if w.minutes+coalesce((select sum(estimated_minutes) from public.quests where user_id=owner_id and source='ai' and due_local_date>=w.week_start and due_local_date<w.week_start+7),0)>budget then raise exception 'This batch exceeds your flexible workload cap of % minutes in the week of %. Include monthly work in that budget.',budget,w.week_start; end if;
  end loop;
  insert into public.generation_runs(user_id,period_type,period_start,timezone,schema_version,payload_hash) values(owner_id,period,start_d,p.timezone,1,md5(batch::text)) returning id into result_id;
  for q in select value from jsonb_array_elements(batch->'quests') loop perform private.create_quest(owner_id,q,'ai',channel,null,result_id); end loop;
  return jsonb_build_object('run_id',result_id,'duplicate',false,'count',q_count);
end $$;

create function private.snapshot(owner_id uuid) returns jsonb
language plpgsql set search_path = '' as $$
declare today date; result jsonb;
begin
  select (now() at time zone timezone)::date into today from public.profiles where user_id=owner_id;
  select jsonb_build_object('today',today,'profile',(select to_jsonb(p) from public.profiles p where user_id=owner_id),'progress',private.progress(owner_id),'stats',(select jsonb_object_agg(stat_tag,stat_xp) from public.character_stats where user_id=owner_id),
    'quests',coalesce((select jsonb_agg(to_jsonb(q) order by q.status,q.due_local_date,q.created_at) from public.quests q where user_id=owner_id and (q.status='pending' or q.due_local_date>=today-90)),'[]'::jsonb),
    'templates',coalesce((select jsonb_agg(to_jsonb(t) order by title) from public.quest_templates t where user_id=owner_id and archived_at is null),'[]'::jsonb),
    'habits',coalesce((select jsonb_agg(to_jsonb(h)||jsonb_build_object('completed_today',exists(select 1 from public.habit_days d where d.habit_id=h.id and d.local_date=today and d.outcome='completed'),'freezes_left',greatest(0,2-(select count(*) from public.habit_days d where d.habit_id=h.id and d.outcome='frozen' and d.local_date>=date_trunc('month',today)::date)), 'week',(select jsonb_agg(coalesce(d.outcome,'pending') order by s.day) from generate_series(today-6,today,interval '1 day') s(day) left join public.habit_days d on d.habit_id=h.id and d.local_date=s.day::date)) order by h.title) from public.habits h where h.user_id=owner_id and archived_at is null),'[]'::jsonb),
    'imports',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from (select * from public.ingestion_events where user_id=owner_id order by created_at desc limit 20) i),'[]'::jsonb),
    'review',private.review(owner_id)) into result;
  return result;
end $$;

-- The only user mutation entry point. Private elevation prevents direct balance edits.
create function private.user_action(action text, args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := auth.uid(); p public.profiles; q public.quests; h public.habits; new_id uuid; today date; tz text; d public.habit_days; result jsonb;
begin
  if owner_id is null then raise exception 'Sign in to continue.' using errcode='42501'; end if;
  perform private.ensure_user(owner_id);
  -- Every mutating path takes the owner lock first. Replays and concurrent requests serialize.
  perform 1 from public.character_progress where user_id=owner_id for update;
  select * into p from public.profiles where user_id=owner_id;
  tz := p.timezone; today := (now() at time zone tz)::date;
  perform private.materialize(owner_id);
  perform private.finalize_habits(owner_id);
  case action
  when 'snapshot' then return private.snapshot(owner_id);
  when 'settings' then
    if not exists(select 1 from pg_catalog.pg_timezone_names where name=args->>'timezone') then raise exception 'Choose a valid time zone, for example Asia/Ulaanbaatar.'; end if;
    update public.profiles set display_name=trim(args->>'display_name'),timezone=args->>'timezone',weekly_capacity=(args->>'weekly_capacity')::integer where user_id=owner_id;
  when 'create_quest' then
    if (args->>'due_local_date')::date<today or (args->>'due_local_date')::date>today+365 then raise exception 'Choose a due date between today and one year from now.'; end if;
    new_id := private.create_quest(owner_id,args);
  when 'create_template' then
    if (args->>'due_local_date')::date<today or (args->>'due_local_date')::date>today+365 then raise exception 'Choose a first due date between today and one year from now.'; end if;
    insert into public.quest_templates(user_id,title,description,stat_tag,cadence,difficulty,estimated_minutes,start_date) values(owner_id,trim(args->>'title'),coalesce(args->>'description',''),args->>'stat_tag',args->>'cadence',(args->>'difficulty')::integer,(args->>'estimated_minutes')::integer,(args->>'due_local_date')::date) returning id into new_id;
    perform private.materialize(owner_id);
  when 'archive_template' then
    update public.quest_templates set archived_at=now() where id=(args->>'id')::uuid and user_id=owner_id;
    if not found then raise exception 'Responsibility not found.'; end if;
  when 'complete_quest','skip_quest' then
    select * into q from public.quests where id=(args->>'id')::uuid and user_id=owner_id for update;
    if not found then raise exception 'Quest not found.'; end if;
    if q.status='completed' and action='complete_quest' then return jsonb_build_object('duplicate',true); end if;
    if q.status<>'pending' then raise exception 'This quest has already been finished or skipped.'; end if;
    if action='complete_quest' then
      update public.quests set status='completed',completed_at=now() where id=q.id;
      insert into public.quest_events(user_id,quest_id,event_type) values(owner_id,q.id,'completed');
      perform private.award(owner_id,'quest:'||q.id,q.stat_tag,q.xp_reward,q.gold_reward,q.id);
    else
      update public.quests set status='skipped' where id=q.id;
      insert into public.quest_events(user_id,quest_id,event_type,reason) values(owner_id,q.id,'skipped',coalesce(args->>'reason',''));
    end if;
  when 'create_habit' then
    insert into public.habits(user_id,title,stat_tag,start_date,last_evaluated) values(owner_id,trim(args->>'title'),args->>'stat_tag',today,today-1) returning id into new_id;
  when 'archive_habit' then
    update public.habits set archived_at=now() where id=(args->>'id')::uuid and user_id=owner_id and archived_at is null;
    if not found then raise exception 'Habit not found.'; end if;
  when 'checkin_habit' then
    select * into h from public.habits where id=(args->>'id')::uuid and user_id=owner_id and archived_at is null for update;
    if not found then raise exception 'Habit not found.'; end if;
    select * into d from public.habit_days where habit_id=h.id and local_date=today;
    if found then return jsonb_build_object('duplicate',true); end if;
    if today<=h.last_evaluated then raise exception 'Your next check-in is available when your local day advances.'; end if;
    insert into public.habit_days(user_id,habit_id,local_date,timezone,outcome) values(owner_id,h.id,today,tz,'completed') returning * into d;
    update public.habits set strength=strength*.9+.1,streak=streak+1,last_evaluated=today where id=h.id;
    perform private.award(owner_id,'habit:'||d.id,h.stat_tag,5,0,null,d.id);
  when 'import_batch' then return private.import_batch(owner_id,args->'batch','paste');
  when 'review_notes' then
    perform private.review(owner_id);
    update public.weekly_reviews set notes=args->>'notes' where user_id=owner_id and week_start=date_trunc('week',today)::date-7;
  else raise exception 'Unknown action.';
  end case;
  return jsonb_build_object('ok',true,'id',new_id);
end $$;

create function public.life_rpg(action text, args jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path = '' as $$ select private.user_action(action,args); $$;

create function private.ingest(owner_id uuid, p_mailbox text, message_id text, batch jsonb, failure text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare result jsonb; existing public.ingestion_events;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Server access only.' using errcode='42501'; end if;
  if length(p_mailbox) not between 1 and 254 or length(message_id) not between 1 and 200 then raise exception 'Invalid ingestion identity.'; end if;
  perform private.ensure_user(owner_id);
  perform 1 from public.character_progress where user_id=owner_id for update;
  select * into existing from public.ingestion_events e where e.user_id=owner_id and e.mailbox=p_mailbox and e.gmail_message_id=message_id;
  if found and existing.status='committed' then return jsonb_build_object('run_id',existing.generation_run_id,'duplicate',true); end if;
  if failure is not null then
    insert into public.ingestion_events(user_id,mailbox,gmail_message_id,status,error) values(owner_id,p_mailbox,message_id,'rejected',left(failure,1000)) on conflict(user_id,mailbox,gmail_message_id) do update set error=excluded.error,status='rejected';
    return jsonb_build_object('rejected',true);
  end if;
  result := private.import_batch(owner_id,batch,'gmail');
  insert into public.ingestion_events(user_id,mailbox,gmail_message_id,generation_run_id,status) values(owner_id,p_mailbox,message_id,(result->>'run_id')::uuid,'committed') on conflict(user_id,mailbox,gmail_message_id) do update set generation_run_id=excluded.generation_run_id,status='committed',error=null;
  return result;
end $$;
create function public.life_rpg_ingest(owner_id uuid, mailbox text, message_id text, batch jsonb default null, failure text default null) returns jsonb
language sql security invoker set search_path = '' as $$ select private.ingest(owner_id,mailbox,message_id,batch,failure); $$;

create function private.maintenance() returns void
language plpgsql security definer set search_path = '' as $$
declare owner_id uuid;
begin
  for owner_id in select user_id from public.profiles loop
    begin
      perform 1 from public.character_progress where user_id=owner_id for update;
      perform private.materialize(owner_id);
      perform private.finalize_habits(owner_id);
      perform private.review(owner_id);
    exception when others then raise warning 'Life RPG maintenance failed for one account: %',sqlstate;
    end;
  end loop;
end $$;

revoke all on all functions in schema private from public,anon,authenticated,service_role;
grant usage on schema private to authenticated,service_role;
grant execute on function private.user_action(text,jsonb) to authenticated;
grant execute on function private.ingest(uuid,text,text,jsonb,text) to service_role;
revoke all on function public.life_rpg(text,jsonb) from public,anon,service_role;
grant execute on function public.life_rpg(text,jsonb) to authenticated;
revoke all on function public.life_rpg_ingest(uuid,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.life_rpg_ingest(uuid,text,text,jsonb,text) to service_role;

-- Hosted Supabase has pg_cron. The standalone PostgreSQL test runtime does not.
do $$ begin
  if exists(select 1 from pg_available_extensions where name='pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('life-rpg-maintenance','*/15 * * * *','select private.maintenance()');
  end if;
end $$;

