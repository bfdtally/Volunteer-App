create or replace function private.register_for_event_impl(
  event_slug text, first_name text, last_name text, email text, phone text default null,
  school text default null, requested_position uuid default null
) returns table(registration_id uuid, secure_token text)
language plpgsql security definer set search_path='' as $$
declare
  ev public.events;
  vol uuid;
  token text;
  reg uuid;
begin
  select * into ev from public.events
  where slug=event_slug and visibility='public' and status='published'
    and (registration_opens_at is null or registration_opens_at<=now())
    and (registration_closes_at is null or registration_closes_at>=now())
  for update;
  if ev.id is null then raise exception 'Registration is not available'; end if;
  if ev.capacity is not null and (
    select count(*) from public.registrations where event_id=ev.id and status='registered'
  )>=ev.capacity then raise exception 'Registration is full'; end if;
  select id into vol from public.volunteers
  where organization_id=ev.organization_id and lower(public.volunteers.email)=lower(register_for_event_impl.email);
  if vol is null then
    insert into public.volunteers(organization_id,first_name,last_name,email,phone,school_organization)
    values(ev.organization_id,trim(first_name),trim(last_name),lower(trim(email)),phone,school)
    returning id into vol;
  end if;
  if exists(select 1 from public.registrations where event_id=ev.id and volunteer_id=vol and status<>'cancelled')
    then raise exception 'Already registered';
  end if;
  token:=encode(extensions.gen_random_bytes(32),'base64');
  insert into public.registrations(organization_id,event_id,volunteer_id,position_id,qr_token_hash)
  values(ev.organization_id,ev.id,vol,requested_position,encode(extensions.digest(token,'sha256'),'hex'))
  returning id into reg;
  return query select reg,token;
end $$;
