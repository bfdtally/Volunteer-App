-- Participant operational hardening and event-scoped staff access.
-- Additive only; volunteer tables and behavior are unchanged.

alter table public.events
  add column if not exists participant_custom_questions jsonb not null default '[]'::jsonb,
  add column if not exists participant_acknowledgments jsonb not null default '[]'::jsonb;

create table if not exists public.event_participant_staff_assignments (
  event_id uuid not null references public.events(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  access_level text not null default 'check_in' check(access_level in('check_in','manage')),
  created_at timestamptz not null default now(),
  primary key(event_id,profile_id)
);
create index if not exists event_participant_staff_profile_idx on public.event_participant_staff_assignments(profile_id,event_id);
alter table public.event_participant_staff_assignments enable row level security;

create or replace function private.has_participant_event_access(target_event uuid, require_manage boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
  select private.is_platform_admin() or exists(
    select 1
    from public.events e
    join public.organization_members m on m.organization_id=e.organization_id and m.status='active'
    join public.profiles p on p.id=m.user_id and p.auth_user_id=(select auth.uid())
    left join public.event_participant_staff_assignments a on a.event_id=e.id and a.profile_id=p.id
    where e.id=target_event and (
      m.role in('owner','administrator')
      or (m.role='event_coordinator' and (e.coordinator_id=p.id or a.profile_id is not null) and (not require_manage or coalesce(a.access_level,'manage')='manage'))
      or (m.role='check_in_staff' and a.profile_id is not null and not require_manage)
    )
  )
$$;
revoke all on function private.has_participant_event_access(uuid,boolean) from public,anon;
grant execute on function private.has_participant_event_access(uuid,boolean) to authenticated;

create policy participant_staff_assignment_read on public.event_participant_staff_assignments for select to authenticated
  using(private.has_participant_event_access(event_id,false));
create policy participant_staff_assignment_insert on public.event_participant_staff_assignments for insert to authenticated
  with check(private.has_participant_event_access(event_id,true));
create policy participant_staff_assignment_update on public.event_participant_staff_assignments for update to authenticated
  using(private.has_participant_event_access(event_id,true)) with check(private.has_participant_event_access(event_id,true));
create policy participant_staff_assignment_delete on public.event_participant_staff_assignments for delete to authenticated
  using(private.has_participant_event_access(event_id,true));

drop policy if exists family_registrations_member_select on public.family_registrations;
drop policy if exists participant_groups_member_select on public.participant_groups;
drop policy if exists participants_member_select on public.participants;
drop policy if exists participant_registrations_member_select on public.participant_registrations;
drop policy if exists participant_attendance_member_select on public.participant_attendance;
create policy family_registrations_event_select on public.family_registrations for select to authenticated using(private.has_participant_event_access(event_id,false));
create policy participant_groups_event_select on public.participant_groups for select to authenticated using(private.has_participant_event_access(event_id,false));
create policy participants_event_select on public.participants for select to authenticated using(exists(select 1 from public.participant_registrations r where r.participant_id=participants.id and private.has_participant_event_access(r.event_id,false)));
create policy participant_registrations_event_select on public.participant_registrations for select to authenticated using(private.has_participant_event_access(event_id,false));
create policy participant_attendance_event_select on public.participant_attendance for select to authenticated using(private.has_participant_event_access(event_id,false));

create table if not exists public.participant_scan_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  participant_registration_id uuid references public.participant_registrations(id) on delete set null,
  group_id uuid references public.participant_groups(id) on delete set null,
  scanned_at timestamptz not null default now(),
  scan_mode text not null check(scan_mode in('checkin','checkout')),
  result text not null check(result in('checked_in','checked_out','duplicate_ignored','invalid','group_found','already_checked_in','not_checked_in')),
  device_session text,
  token_fingerprint text not null
);
create index if not exists participant_scan_events_lookup_idx on public.participant_scan_events(event_id,token_fingerprint,scanned_at desc);
create index if not exists participant_scan_events_org_idx on public.participant_scan_events(organization_id,scanned_at desc);
alter table public.participant_scan_events enable row level security;
create policy participant_scan_events_select on public.participant_scan_events for select to authenticated
  using(private.has_participant_event_access(event_id,false));
create policy participant_scan_events_insert on public.participant_scan_events for insert to authenticated
  with check(private.has_participant_event_access(event_id,false));

grant select,insert,update,delete on public.event_participant_staff_assignments to authenticated;
grant select,insert on public.participant_scan_events to authenticated;
grant usage,select on sequence public.participant_scan_events_id_seq to authenticated;

create or replace function private.scan_participant_credential_impl(event_id uuid, secure_token text, scan_mode text default 'checkin', device_session text default null)
returns table(action text, credential_type text, participant_registration_id uuid, group_id uuid, participant_first_name text, participant_last_name text, participant_school text, participant_grade text, occurred_at timestamptz, message text)
language plpgsql security definer set search_path='' as $$
declare
  ev public.events; reg public.participant_registrations; person public.participants; grp public.participant_groups; active public.participant_attendance; actor uuid; fingerprint text; happened timestamptz:=statement_timestamp(); last_scan timestamptz;
begin
  if (select auth.uid()) is null then raise exception 'Authentication is required'; end if;
  if scan_mode not in('checkin','checkout') then raise exception 'Scan mode must be checkin or checkout'; end if;
  select * into ev from public.events e where e.id=scan_participant_credential_impl.event_id and private.has_participant_event_access(e.id,false);
  if ev.id is null then raise exception 'Event not found or access denied'; end if;
  actor:=private.current_profile_id(); fingerprint:=encode(extensions.digest(secure_token,'sha256'),'hex');
  select scanned_at into last_scan from public.participant_scan_events s where s.event_id=ev.id and s.token_fingerprint=fingerprint and s.scan_mode=scan_participant_credential_impl.scan_mode and s.device_session is not distinct from left(scan_participant_credential_impl.device_session,100) order by scanned_at desc limit 1;
  if last_scan is not null and last_scan>happened-interval '2 seconds' then
    insert into public.participant_scan_events(organization_id,event_id,scanned_at,scan_mode,result,device_session,token_fingerprint) values(ev.organization_id,ev.id,happened,scan_mode,'duplicate_ignored',left(device_session,100),fingerprint);
    return query select 'duplicate_ignored'::text,'participant'::text,null::uuid,null::uuid,null::text,null::text,null::text,null::text,happened,'Duplicate scan ignored. Ready for the next person.'::text; return;
  end if;
  select * into grp from public.participant_groups g where g.event_id=ev.id and g.qr_token_hash=fingerprint limit 1;
  if grp.id is not null then
    insert into public.participant_scan_events(organization_id,event_id,group_id,scanned_at,scan_mode,result,device_session,token_fingerprint) values(ev.organization_id,ev.id,grp.id,happened,scan_mode,'group_found',left(device_session,100),fingerprint);
    return query select 'group_found'::text,'group'::text,null::uuid,grp.id,null::text,null::text,grp.name,null::text,happened,(grp.name||' roster opened.')::text; return;
  end if;
  select * into reg from public.participant_registrations r where r.event_id=ev.id and r.qr_token_hash=fingerprint limit 1;
  if reg.id is null then
    insert into public.participant_scan_events(organization_id,event_id,scanned_at,scan_mode,result,device_session,token_fingerprint) values(ev.organization_id,ev.id,happened,scan_mode,'invalid',left(device_session,100),fingerprint);
    return query select 'invalid'::text,'invalid'::text,null::uuid,null::uuid,null::text,null::text,null::text,null::text,happened,'This is not a valid participant or group credential.'::text; return;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(reg.id::text,0));
  select * into person from public.participants p where p.id=reg.participant_id;
  select * into active from public.participant_attendance a where a.participant_registration_id=reg.id and a.status='open' and a.checked_out_at is null order by a.checked_in_at desc limit 1 for update;
  if scan_mode='checkin' and active.id is not null then
    insert into public.participant_scan_events(organization_id,event_id,participant_registration_id,scanned_at,scan_mode,result,device_session,token_fingerprint) values(ev.organization_id,ev.id,reg.id,happened,scan_mode,'already_checked_in',left(device_session,100),fingerprint);
    return query select 'already_checked_in'::text,'participant'::text,reg.id,null::uuid,person.first_name,person.last_name,person.school,person.grade,active.checked_in_at,(person.first_name||' '||person.last_name||' is already checked in.')::text; return;
  end if;
  if scan_mode='checkout' and active.id is null then
    insert into public.participant_scan_events(organization_id,event_id,participant_registration_id,scanned_at,scan_mode,result,device_session,token_fingerprint) values(ev.organization_id,ev.id,reg.id,happened,scan_mode,'not_checked_in',left(device_session,100),fingerprint);
    return query select 'not_checked_in'::text,'participant'::text,reg.id,null::uuid,person.first_name,person.last_name,person.school,person.grade,happened,(person.first_name||' '||person.last_name||' is not checked in.')::text; return;
  end if;
  if scan_mode='checkin' then
    insert into public.participant_attendance(organization_id,event_id,participant_registration_id,checked_in_at,check_in_method,checked_in_by,device_session) values(ev.organization_id,ev.id,reg.id,happened,'individual_qr',actor,left(device_session,100));
  else
    update public.participant_attendance set checked_out_at=happened,check_out_method='individual_qr',checked_out_by=actor,status='closed',updated_at=happened where id=active.id;
  end if;
  insert into public.participant_scan_events(organization_id,event_id,participant_registration_id,scanned_at,scan_mode,result,device_session,token_fingerprint) values(ev.organization_id,ev.id,reg.id,happened,scan_mode,case when scan_mode='checkin' then 'checked_in' else 'checked_out' end,left(device_session,100),fingerprint);
  insert into public.audit_logs(organization_id,event_id,actor_id,action,entity_type,entity_id,new_values) values(ev.organization_id,ev.id,actor,case when scan_mode='checkin' then 'participant_checked_in' else 'participant_checked_out' end,'participant_registration',reg.id,jsonb_build_object('method','individual_qr','device_session',left(device_session,100)));
  return query select case when scan_mode='checkin' then 'checked_in' else 'checked_out' end,'participant'::text,reg.id,null::uuid,person.first_name,person.last_name,person.school,person.grade,happened,(person.first_name||' '||person.last_name||case when scan_mode='checkin' then ' checked in.' else ' checked out.' end)::text;
end $$;

create or replace function public.set_participant_attendance(registration_ids uuid[], attendance_mode text, attendance_method text, device_session text default null)
returns integer language plpgsql security invoker set search_path='' as $$
declare rid uuid; reg public.participant_registrations; actor uuid:=private.current_profile_id(); changed integer:=0; active_id uuid; now_at timestamptz:=statement_timestamp(); event_for_audit uuid; org_for_audit uuid;
begin
  if (select auth.uid()) is null or attendance_mode not in('checkin','checkout') or attendance_method not in('family_checkin','group_checkin','manual','walk_in','admin_correction') then raise exception 'Invalid attendance request'; end if;
  foreach rid in array registration_ids loop
    select * into reg from public.participant_registrations r where r.id=rid and private.has_participant_event_access(r.event_id,false);
    if reg.id is null then continue; end if;
    event_for_audit:=reg.event_id; org_for_audit:=reg.organization_id;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(reg.id::text,0));
    select id into active_id from public.participant_attendance where participant_registration_id=rid and status='open' and checked_out_at is null limit 1 for update;
    if attendance_mode='checkin' and active_id is null then
      insert into public.participant_attendance(organization_id,event_id,participant_registration_id,checked_in_at,check_in_method,checked_in_by,device_session) values(reg.organization_id,reg.event_id,reg.id,now_at,attendance_method,actor,left(device_session,100)); changed:=changed+1;
    elsif attendance_mode='checkout' and active_id is not null then
      update public.participant_attendance set checked_out_at=now_at,check_out_method=attendance_method,checked_out_by=actor,status='closed',updated_at=now_at where id=active_id; changed:=changed+1;
    end if;
  end loop;
  if changed>0 then insert into public.audit_logs(organization_id,event_id,actor_id,action,entity_type,new_values) values(org_for_audit,event_for_audit,actor,'participant_bulk_'||attendance_mode,'participant_attendance',jsonb_build_object('method',attendance_method,'changed',changed,'registration_ids',registration_ids)); end if;
  return changed;
end $$;

create or replace function public.register_participant_walk_in(target_event uuid, participant_data jsonb, target_group uuid default null)
returns table(participant_registration_id uuid, secure_token text)
language plpgsql security definer set search_path='' as $$
declare ev public.events; person uuid; reg uuid; token text; actor uuid:=private.current_profile_id(); current_count integer;
begin
  if (select auth.uid()) is null then raise exception 'Authentication is required'; end if;
  select * into ev from public.events e where e.id=target_event and e.allow_participant_walk_ins and private.has_participant_event_access(e.id,false) for update;
  if ev.id is null then raise exception 'Participant walk-ins are unavailable or access is denied'; end if;
  if nullif(trim(participant_data->>'first_name'),'') is null or nullif(trim(participant_data->>'last_name'),'') is null then raise exception 'Participant name is required'; end if;
  select count(*) into current_count from public.participant_registrations where event_id=ev.id and status='registered';
  if ev.participant_capacity is not null and current_count>=ev.participant_capacity then raise exception 'Participant registration is full'; end if;
  if target_group is not null and not exists(select 1 from public.participant_groups g where g.id=target_group and g.event_id=ev.id) then raise exception 'Group not found'; end if;
  insert into public.participants(organization_id,first_name,last_name,school,grade,accommodations) values(ev.organization_id,trim(participant_data->>'first_name'),trim(participant_data->>'last_name'),nullif(trim(participant_data->>'school'),''),nullif(trim(participant_data->>'grade'),''),nullif(trim(participant_data->>'accommodations'),'')) returning id into person;
  token:=private.new_participant_token();
  insert into public.participant_registrations(organization_id,event_id,participant_id,registration_type,group_id,qr_token_hash,responses) values(ev.organization_id,ev.id,person,'walk_in',target_group,encode(extensions.digest(token,'sha256'),'hex'),coalesce(participant_data->'responses','{}'::jsonb)) returning id into reg;
  insert into public.participant_attendance(organization_id,event_id,participant_registration_id,checked_in_at,check_in_method,checked_in_by,device_session) values(ev.organization_id,ev.id,reg,statement_timestamp(),'walk_in',actor,'walk-in');
  insert into public.audit_logs(organization_id,event_id,actor_id,action,entity_type,entity_id,new_values) values(ev.organization_id,ev.id,actor,'participant_walk_in_registered','participant_registration',reg,jsonb_build_object('group_id',target_group));
  return query select reg,token;
end $$;
revoke all on function public.register_participant_walk_in(uuid,jsonb,uuid) from public,anon;
grant execute on function public.register_participant_walk_in(uuid,jsonb,uuid) to authenticated;
