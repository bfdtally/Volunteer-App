alter table public.events
  add column logo_url text,
  add column primary_color text not null default '#163a5f' check (primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  add column secondary_color text not null default '#ef7b45' check (secondary_color ~ '^#[0-9A-Fa-f]{6}$');

create table public.registration_occurrences (
  registration_id uuid not null references public.registrations(id) on delete cascade,
  occurrence_id uuid not null references public.event_occurrences(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (registration_id, occurrence_id)
);
alter table public.registration_occurrences enable row level security;
create policy registration_occurrences_member_read on public.registration_occurrences for select to authenticated
using (exists(select 1 from public.registrations r where r.id=registration_id and private.has_org_role(r.organization_id,null)));
grant select on public.registration_occurrences to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('event-logos','event-logos',true,5242880,array['image/png','image/jpeg','image/webp','image/svg+xml'])
on conflict(id) do update set public=true,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create policy event_logos_public_read on storage.objects for select to public using(bucket_id='event-logos');
create policy event_logos_member_insert on storage.objects for insert to authenticated
with check(bucket_id='event-logos' and private.has_org_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy event_logos_member_update on storage.objects for update to authenticated
using(bucket_id='event-logos' and private.has_org_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','event_coordinator']::public.member_role[]))
with check(bucket_id='event-logos' and private.has_org_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy event_logos_member_delete on storage.objects for delete to authenticated
using(bucket_id='event-logos' and private.has_org_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','event_coordinator']::public.member_role[]));

create function private.register_for_event_schedule_impl(
  event_slug text, first_name text, last_name text, email text, phone text default null,
  school text default null, requested_position uuid default null, occurrence_ids uuid[] default null
) returns table(registration_id uuid,secure_token text)
language plpgsql security definer set search_path='' as $$
declare result record;
begin
  select * into result from private.register_for_event_impl(event_slug,first_name,last_name,email,phone,school,requested_position);
  if occurrence_ids is not null then
    if exists(
      select 1 from unnest(occurrence_ids) chosen
      where not exists(
        select 1 from public.event_occurrences o join public.registrations r on r.event_id=o.event_id
        where o.id=chosen and r.id=result.registration_id and o.status='scheduled'
      )
    ) then raise exception 'Invalid event day selected'; end if;
    insert into public.registration_occurrences(registration_id,occurrence_id)
    select result.registration_id,chosen from unnest(occurrence_ids) chosen on conflict do nothing;
  end if;
  return query select result.registration_id,result.secure_token;
end $$;
revoke all on function private.register_for_event_schedule_impl(text,text,text,text,text,text,uuid,uuid[]) from public,anon,authenticated;
grant execute on function private.register_for_event_schedule_impl(text,text,text,text,text,text,uuid,uuid[]) to anon,authenticated;

create function public.register_for_event_schedule(
  event_slug text, first_name text, last_name text, email text, phone text default null,
  school text default null, requested_position uuid default null, occurrence_ids uuid[] default null
) returns table(registration_id uuid,secure_token text)
language sql security invoker set search_path='' as $$
select * from private.register_for_event_schedule_impl(event_slug,first_name,last_name,email,phone,school,requested_position,occurrence_ids)
$$;
revoke all on function public.register_for_event_schedule(text,text,text,text,text,text,uuid,uuid[]) from public;
grant execute on function public.register_for_event_schedule(text,text,text,text,text,text,uuid,uuid[]) to anon,authenticated;
