create type public.opportunity_type as enum ('one_time', 'multi_day', 'ongoing_program');

alter table public.events
  add column opportunity_type public.opportunity_type not null default 'one_time',
  add column end_date date,
  add column program_term text,
  add column availability_mode text not null default 'fixed' check (availability_mode in ('fixed','flexible','scheduled','assigned')),
  add column availability_notes text,
  add column attendance_mode text not null default 'event_checkin' check (attendance_mode in ('event_checkin','program_signin')),
  add constraint events_date_range_valid check (end_date is null or end_date >= date),
  add constraint events_type_schedule_valid check (
    (opportunity_type = 'one_time' and attendance_mode = 'event_checkin') or
    (opportunity_type = 'multi_day' and end_date is not null and attendance_mode = 'event_checkin') or
    (opportunity_type = 'ongoing_program' and end_date is not null and attendance_mode = 'program_signin')
  );

create table public.event_occurrences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  location text,
  instructions text,
  status text not null default 'scheduled' check (status in ('scheduled','cancelled','completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  unique (event_id, starts_at)
);

create index event_occurrences_organization_id_idx on public.event_occurrences(organization_id);
create index event_occurrences_event_id_starts_at_idx on public.event_occurrences(event_id, starts_at);

alter table public.event_occurrences enable row level security;

create policy event_occurrences_public_read on public.event_occurrences for select to anon
using (exists(select 1 from public.events e where e.id=event_id and e.visibility='public' and e.status in('published','registration_closed','in_progress','cancelled')));
create policy event_occurrences_member_read on public.event_occurrences for select to authenticated using(private.has_org_role(organization_id,null));
create policy event_occurrences_member_insert on public.event_occurrences for insert to authenticated with check(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy event_occurrences_member_update on public.event_occurrences for update to authenticated using(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[])) with check(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy event_occurrences_member_delete on public.event_occurrences for delete to authenticated using(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));

grant select on public.event_occurrences to anon;
grant select,insert,update,delete on public.event_occurrences to authenticated;
