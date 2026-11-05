-- Participant Module foundation. Additive only; volunteer records and workflows are unchanged.

alter table public.events
  add column if not exists participant_registration_enabled boolean not null default false,
  add column if not exists participant_registration_modes text[] not null default array['individual_family']::text[],
  add column if not exists participant_registration_opens_at timestamptz,
  add column if not exists participant_registration_closes_at timestamptz,
  add column if not exists participant_capacity integer,
  add column if not exists allow_participant_walk_ins boolean not null default false,
  add column if not exists participant_require_checkout boolean not null default true,
  add column if not exists allow_family_checkin boolean not null default true,
  add column if not exists allow_group_checkin boolean not null default true,
  add column if not exists allow_individual_participant_qr boolean not null default true,
  add column if not exists participant_guardian_required boolean not null default true,
  add column if not exists participant_emergency_contact_required boolean not null default false,
  add column if not exists participant_school_required boolean not null default true,
  add column if not exists participant_grade_required boolean not null default true,
  add constraint events_participant_capacity_positive check(participant_capacity is null or participant_capacity > 0),
  add constraint events_participant_modes_valid check(
    participant_registration_modes <@ array['individual_family','school_group']::text[]
    and cardinality(participant_registration_modes) > 0
  );

create table public.family_registrations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  guardian_first_name text not null,
  guardian_last_name text not null,
  guardian_email text not null,
  guardian_phone text,
  address jsonb not null default '{}'::jsonb,
  emergency_contact jsonb not null default '{}'::jsonb,
  status text not null default 'registered' check(status in('registered','cancelled','needs_attention')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.participant_groups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null,
  group_type text not null default 'school',
  coordinator_first_name text not null,
  coordinator_last_name text not null,
  coordinator_email text not null,
  coordinator_phone text,
  expected_participant_count integer not null default 0 check(expected_participant_count >= 0),
  chaperone_count integer not null default 0 check(chaperone_count >= 0),
  address jsonb not null default '{}'::jsonb,
  responses jsonb not null default '{}'::jsonb,
  status text not null default 'registered' check(status in('registered','arrived','departed','cancelled','needs_attention')),
  qr_token_hash text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.participants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  first_name text not null,
  last_name text not null,
  school text,
  grade text,
  age integer check(age is null or age between 2 and 25),
  accommodations text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.participant_registrations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  participant_id uuid not null references public.participants(id) on delete cascade,
  registration_type text not null check(registration_type in('individual_family','school_group','walk_in')),
  family_registration_id uuid references public.family_registrations(id) on delete set null,
  group_id uuid references public.participant_groups(id) on delete set null,
  status text not null default 'registered' check(status in('registered','cancelled','needs_attention')),
  qr_token_hash text not null unique,
  responses jsonb not null default '{}'::jsonb,
  registered_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(
    (registration_type='individual_family' and family_registration_id is not null and group_id is null)
    or (registration_type='school_group' and group_id is not null and family_registration_id is null)
    or registration_type='walk_in'
  )
);

create table public.participant_attendance (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  participant_registration_id uuid not null references public.participant_registrations(id) on delete cascade,
  checked_in_at timestamptz not null default now(),
  checked_out_at timestamptz,
  check_in_method text not null check(check_in_method in('individual_qr','family_checkin','group_checkin','manual','walk_in','admin_correction')),
  check_out_method text check(check_out_method is null or check_out_method in('individual_qr','family_checkin','group_checkin','manual','admin_correction')),
  checked_in_by uuid references public.profiles(id),
  checked_out_by uuid references public.profiles(id),
  device_session text,
  status text not null default 'open' check(status in('open','closed','corrected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(checked_out_at is null or checked_out_at >= checked_in_at)
);

create unique index participant_attendance_one_open
  on public.participant_attendance(participant_registration_id) where checked_out_at is null and status='open';
create index participant_registrations_event on public.participant_registrations(event_id, registration_type, status);
create index participant_registrations_family on public.participant_registrations(family_registration_id) where family_registration_id is not null;
create index participant_registrations_group on public.participant_registrations(group_id) where group_id is not null;
create index participant_attendance_event on public.participant_attendance(event_id, checked_in_at desc);
create index participants_org_name on public.participants(organization_id, last_name, first_name);

alter table public.family_registrations enable row level security;
alter table public.participant_groups enable row level security;
alter table public.participants enable row level security;
alter table public.participant_registrations enable row level security;
alter table public.participant_attendance enable row level security;

create policy family_registrations_member_select on public.family_registrations for select to authenticated
  using(private.has_org_role(organization_id,null));
create policy family_registrations_manager_all on public.family_registrations for all to authenticated
  using(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]))
  with check(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy participant_groups_member_select on public.participant_groups for select to authenticated
  using(private.has_org_role(organization_id,null));
create policy participant_groups_manager_all on public.participant_groups for all to authenticated
  using(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]))
  with check(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy participants_member_select on public.participants for select to authenticated
  using(private.has_org_role(organization_id,null));
create policy participants_manager_all on public.participants for all to authenticated
  using(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]))
  with check(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy participant_registrations_member_select on public.participant_registrations for select to authenticated
  using(private.has_org_role(organization_id,null));
create policy participant_registrations_manager_all on public.participant_registrations for all to authenticated
  using(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]))
  with check(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy participant_attendance_member_select on public.participant_attendance for select to authenticated
  using(private.has_org_role(organization_id,null));
create policy participant_attendance_staff_all on public.participant_attendance for all to authenticated
  using(private.has_org_role(organization_id,null))
  with check(private.has_org_role(organization_id,null));

create or replace function private.new_participant_token() returns text
language sql volatile security invoker set search_path='' as $$
  select pg_catalog.translate(pg_catalog.rtrim(encode(extensions.gen_random_bytes(24),'base64'),'='),'+/','-_')
$$;
revoke all on function private.new_participant_token() from public, anon, authenticated;

create or replace function private.register_participant_family_impl(event_slug text, guardian jsonb, children jsonb)
returns table(family_registration_id uuid, credentials jsonb)
language plpgsql security definer set search_path='' as $$
declare
  ev public.events; fam uuid; child jsonb; person uuid; reg uuid; token text; output jsonb := '[]'::jsonb; current_count integer;
begin
  select * into ev from public.events e where e.slug=event_slug and e.visibility='public' and e.status='published'
    and e.participant_registration_enabled and 'individual_family'=any(e.participant_registration_modes)
    and (e.participant_registration_opens_at is null or e.participant_registration_opens_at<=now())
    and (e.participant_registration_closes_at is null or e.participant_registration_closes_at>=now()) for update;
  if ev.id is null then raise exception 'Participant registration is not available'; end if;
  if jsonb_typeof(children)<>'array' or jsonb_array_length(children)<1 or jsonb_array_length(children)>20 then
    raise exception 'Add between 1 and 20 participants';
  end if;
  select count(*) into current_count from public.participant_registrations where event_id=ev.id and status='registered';
  if ev.participant_capacity is not null and current_count+jsonb_array_length(children)>ev.participant_capacity then
    raise exception 'Participant registration is full';
  end if;
  if nullif(trim(guardian->>'first_name'),'') is null or nullif(trim(guardian->>'last_name'),'') is null
    or nullif(trim(guardian->>'email'),'') is null then raise exception 'Guardian name and email are required'; end if;
  insert into public.family_registrations(organization_id,event_id,guardian_first_name,guardian_last_name,guardian_email,guardian_phone,address,emergency_contact)
  values(ev.organization_id,ev.id,trim(guardian->>'first_name'),trim(guardian->>'last_name'),lower(trim(guardian->>'email')),
    nullif(trim(guardian->>'phone'),''),coalesce(guardian->'address','{}'::jsonb),coalesce(guardian->'emergency_contact','{}'::jsonb)) returning id into fam;
  for child in select value from jsonb_array_elements(children) loop
    if nullif(trim(child->>'first_name'),'') is null or nullif(trim(child->>'last_name'),'') is null then raise exception 'Every participant needs a name'; end if;
    if ev.participant_school_required and nullif(trim(child->>'school'),'') is null then raise exception 'School is required for every participant'; end if;
    if ev.participant_grade_required and nullif(trim(child->>'grade'),'') is null then raise exception 'Grade is required for every participant'; end if;
    insert into public.participants(organization_id,first_name,last_name,school,grade,age,accommodations)
    values(ev.organization_id,trim(child->>'first_name'),trim(child->>'last_name'),nullif(trim(child->>'school'),''),nullif(trim(child->>'grade'),''),
      case when child->>'age' ~ '^[0-9]+$' then (child->>'age')::integer else null end,nullif(trim(child->>'accommodations'),'')) returning id into person;
    token:=private.new_participant_token();
    insert into public.participant_registrations(organization_id,event_id,participant_id,registration_type,family_registration_id,qr_token_hash,responses)
    values(ev.organization_id,ev.id,person,'individual_family',fam,encode(extensions.digest(token,'sha256'),'hex'),coalesce(child->'responses','{}'::jsonb)) returning id into reg;
    output:=output||jsonb_build_array(jsonb_build_object('participant_registration_id',reg,'participant_id',person,'first_name',trim(child->>'first_name'),'last_name',trim(child->>'last_name'),'secure_token',token));
  end loop;
  insert into public.audit_logs(organization_id,event_id,action,entity_type,entity_id,new_values)
  values(ev.organization_id,ev.id,'participant_family_registered','family_registration',fam,jsonb_build_object('participant_count',jsonb_array_length(children)));
  return query select fam,output;
end $$;
revoke all on function private.register_participant_family_impl(text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function private.register_participant_family_impl(text,jsonb,jsonb) to anon,authenticated;

create or replace function public.register_participant_family(event_slug text, guardian jsonb, children jsonb)
returns table(family_registration_id uuid, credentials jsonb)
language sql security invoker set search_path='' as $$
  select * from private.register_participant_family_impl(event_slug,guardian,children)
$$;
revoke all on function public.register_participant_family(text,jsonb,jsonb) from public;
grant execute on function public.register_participant_family(text,jsonb,jsonb) to anon,authenticated;

create or replace function private.register_participant_group_impl(event_slug text, group_data jsonb, roster jsonb)
returns table(group_id uuid, group_secure_token text, credentials jsonb)
language plpgsql security definer set search_path='' as $$
declare
  ev public.events; grp uuid; row_data jsonb; person uuid; reg uuid; token text; group_token text; output jsonb:='[]'::jsonb; current_count integer;
begin
  select * into ev from public.events e where e.slug=event_slug and e.visibility='public' and e.status='published'
    and e.participant_registration_enabled and 'school_group'=any(e.participant_registration_modes)
    and (e.participant_registration_opens_at is null or e.participant_registration_opens_at<=now())
    and (e.participant_registration_closes_at is null or e.participant_registration_closes_at>=now()) for update;
  if ev.id is null then raise exception 'Group registration is not available'; end if;
  if jsonb_typeof(roster)<>'array' or jsonb_array_length(roster)<1 or jsonb_array_length(roster)>500 then raise exception 'Add between 1 and 500 participants'; end if;
  select count(*) into current_count from public.participant_registrations where event_id=ev.id and status='registered';
  if ev.participant_capacity is not null and current_count+jsonb_array_length(roster)>ev.participant_capacity then raise exception 'Participant registration is full'; end if;
  if nullif(trim(group_data->>'name'),'') is null or nullif(trim(group_data->>'coordinator_first_name'),'') is null
    or nullif(trim(group_data->>'coordinator_last_name'),'') is null or nullif(trim(group_data->>'coordinator_email'),'') is null then
    raise exception 'Group and coordinator information is required'; end if;
  group_token:=private.new_participant_token();
  insert into public.participant_groups(organization_id,event_id,name,group_type,coordinator_first_name,coordinator_last_name,coordinator_email,coordinator_phone,expected_participant_count,chaperone_count,qr_token_hash,responses)
  values(ev.organization_id,ev.id,trim(group_data->>'name'),coalesce(nullif(trim(group_data->>'group_type'),''),'school'),trim(group_data->>'coordinator_first_name'),trim(group_data->>'coordinator_last_name'),lower(trim(group_data->>'coordinator_email')),nullif(trim(group_data->>'coordinator_phone'),''),jsonb_array_length(roster),coalesce((group_data->>'chaperone_count')::integer,0),encode(extensions.digest(group_token,'sha256'),'hex'),coalesce(group_data->'responses','{}'::jsonb)) returning id into grp;
  for row_data in select value from jsonb_array_elements(roster) loop
    if nullif(trim(row_data->>'first_name'),'') is null or nullif(trim(row_data->>'last_name'),'') is null then raise exception 'Every roster row needs a participant name'; end if;
    insert into public.participants(organization_id,first_name,last_name,school,grade,age,accommodations)
    values(ev.organization_id,trim(row_data->>'first_name'),trim(row_data->>'last_name'),coalesce(nullif(trim(row_data->>'school'),''),trim(group_data->>'name')),nullif(trim(row_data->>'grade'),''),case when row_data->>'age'~'^[0-9]+$' then (row_data->>'age')::integer else null end,nullif(trim(row_data->>'accommodations'),'')) returning id into person;
    token:=private.new_participant_token();
    insert into public.participant_registrations(organization_id,event_id,participant_id,registration_type,group_id,qr_token_hash,responses)
    values(ev.organization_id,ev.id,person,'school_group',grp,encode(extensions.digest(token,'sha256'),'hex'),coalesce(row_data->'responses','{}'::jsonb)) returning id into reg;
    output:=output||jsonb_build_array(jsonb_build_object('participant_registration_id',reg,'participant_id',person,'first_name',trim(row_data->>'first_name'),'last_name',trim(row_data->>'last_name'),'secure_token',token));
  end loop;
  insert into public.audit_logs(organization_id,event_id,action,entity_type,entity_id,new_values)
  values(ev.organization_id,ev.id,'participant_group_registered','participant_group',grp,jsonb_build_object('participant_count',jsonb_array_length(roster)));
  return query select grp,group_token,output;
end $$;
revoke all on function private.register_participant_group_impl(text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function private.register_participant_group_impl(text,jsonb,jsonb) to anon,authenticated;

create or replace function public.register_participant_group(event_slug text, group_data jsonb, roster jsonb)
returns table(group_id uuid, group_secure_token text, credentials jsonb)
language sql security invoker set search_path='' as $$
  select * from private.register_participant_group_impl(event_slug,group_data,roster)
$$;
revoke all on function public.register_participant_group(text,jsonb,jsonb) from public;
grant execute on function public.register_participant_group(text,jsonb,jsonb) to anon,authenticated;

create or replace function private.scan_participant_credential_impl(event_id uuid, secure_token text, scan_mode text default 'checkin', device_session text default null)
returns table(action text, credential_type text, participant_registration_id uuid, group_id uuid, participant_first_name text, participant_last_name text, participant_school text, participant_grade text, occurred_at timestamptz, message text)
language plpgsql security definer set search_path='' as $$
declare
  ev public.events; reg public.participant_registrations; person public.participants; grp public.participant_groups; active public.participant_attendance; actor uuid; fingerprint text; happened timestamptz:=statement_timestamp();
begin
  if (select auth.uid()) is null then raise exception 'Authentication is required'; end if;
  if scan_mode not in('checkin','checkout') then raise exception 'Scan mode must be checkin or checkout'; end if;
  select * into ev from public.events e where e.id=scan_participant_credential_impl.event_id and private.has_org_role(e.organization_id,null);
  if ev.id is null then raise exception 'Event not found or access denied'; end if;
  actor:=private.current_profile_id(); fingerprint:=encode(extensions.digest(secure_token,'sha256'),'hex');
  select * into grp from public.participant_groups g where g.event_id=ev.id and g.qr_token_hash=fingerprint limit 1;
  if grp.id is not null then
    return query select 'group_found'::text,'group'::text,null::uuid,grp.id,null::text,null::text,grp.name,null::text,happened,(grp.name||' roster opened.')::text; return;
  end if;
  select * into reg from public.participant_registrations r where r.event_id=ev.id and r.qr_token_hash=fingerprint limit 1;
  if reg.id is null then return query select 'invalid'::text,'invalid'::text,null::uuid,null::uuid,null::text,null::text,null::text,null::text,happened,'This is not a valid participant or group credential.'::text; return; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(reg.id::text,0));
  select * into person from public.participants p where p.id=reg.participant_id;
  select * into active from public.participant_attendance a where a.participant_registration_id=reg.id and a.status='open' and a.checked_out_at is null order by a.checked_in_at desc limit 1 for update;
  if scan_mode='checkin' and active.id is not null then return query select 'already_checked_in'::text,'participant'::text,reg.id,null::uuid,person.first_name,person.last_name,person.school,person.grade,active.checked_in_at,(person.first_name||' '||person.last_name||' is already checked in.')::text; return; end if;
  if scan_mode='checkout' and active.id is null then return query select 'not_checked_in'::text,'participant'::text,reg.id,null::uuid,person.first_name,person.last_name,person.school,person.grade,happened,(person.first_name||' '||person.last_name||' is not checked in.')::text; return; end if;
  if scan_mode='checkin' then
    insert into public.participant_attendance(organization_id,event_id,participant_registration_id,checked_in_at,check_in_method,checked_in_by,device_session)
    values(ev.organization_id,ev.id,reg.id,happened,'individual_qr',actor,left(device_session,100));
  else
    update public.participant_attendance set checked_out_at=happened,check_out_method='individual_qr',checked_out_by=actor,status='closed',updated_at=happened where id=active.id;
  end if;
  insert into public.audit_logs(organization_id,event_id,actor_id,action,entity_type,entity_id,new_values)
  values(ev.organization_id,ev.id,actor,case when scan_mode='checkin' then 'participant_checked_in' else 'participant_checked_out' end,'participant_registration',reg.id,jsonb_build_object('method','individual_qr','device_session',left(device_session,100)));
  return query select case when scan_mode='checkin' then 'checked_in' else 'checked_out' end,'participant'::text,reg.id,null::uuid,person.first_name,person.last_name,person.school,person.grade,happened,(person.first_name||' '||person.last_name||case when scan_mode='checkin' then ' checked in.' else ' checked out.' end)::text;
end $$;
revoke all on function private.scan_participant_credential_impl(uuid,text,text,text) from public,anon,authenticated;
grant execute on function private.scan_participant_credential_impl(uuid,text,text,text) to authenticated;

create or replace function public.scan_participant_credential(event_id uuid, secure_token text, scan_mode text default 'checkin', device_session text default null)
returns table(action text, credential_type text, participant_registration_id uuid, group_id uuid, participant_first_name text, participant_last_name text, participant_school text, participant_grade text, occurred_at timestamptz, message text)
language sql security invoker set search_path='' as $$ select * from private.scan_participant_credential_impl(event_id,secure_token,scan_mode,device_session) $$;
revoke all on function public.scan_participant_credential(uuid,text,text,text) from public,anon;
grant execute on function public.scan_participant_credential(uuid,text,text,text) to authenticated;

create or replace function public.set_participant_attendance(registration_ids uuid[], attendance_mode text, attendance_method text, device_session text default null)
returns integer language plpgsql security invoker set search_path='' as $$
declare rid uuid; reg public.participant_registrations; actor uuid:=private.current_profile_id(); changed integer:=0; active_id uuid; now_at timestamptz:=statement_timestamp();
begin
  if (select auth.uid()) is null or attendance_mode not in('checkin','checkout') or attendance_method not in('family_checkin','group_checkin','manual','walk_in','admin_correction') then raise exception 'Invalid attendance request'; end if;
  foreach rid in array registration_ids loop
    select * into reg from public.participant_registrations r where r.id=rid and private.has_org_role(r.organization_id,null);
    if reg.id is null then continue; end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(reg.id::text,0));
    select id into active_id from public.participant_attendance where participant_registration_id=rid and status='open' and checked_out_at is null limit 1 for update;
    if attendance_mode='checkin' and active_id is null then
      insert into public.participant_attendance(organization_id,event_id,participant_registration_id,checked_in_at,check_in_method,checked_in_by,device_session)
      values(reg.organization_id,reg.event_id,reg.id,now_at,attendance_method,actor,left(device_session,100)); changed:=changed+1;
    elsif attendance_mode='checkout' and active_id is not null then
      update public.participant_attendance set checked_out_at=now_at,check_out_method=attendance_method,checked_out_by=actor,status='closed',updated_at=now_at where id=active_id; changed:=changed+1;
    end if;
  end loop;
  return changed;
end $$;
revoke all on function public.set_participant_attendance(uuid[],text,text,text) from public,anon;
grant execute on function public.set_participant_attendance(uuid[],text,text,text) to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.participant_attendance;
exception when duplicate_object then null; end $$;

