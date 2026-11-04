create or replace function private.scan_event_credential_impl(
  event_id uuid,
  secure_token text,
  scan_mode text default 'checkin',
  device_session text default null
)
returns table (
  action text,
  registration_id uuid,
  volunteer_first_name text,
  volunteer_last_name text,
  attendance_session_id uuid,
  occurred_at timestamptz,
  message text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  ev public.events;
  reg public.registrations;
  volunteer public.volunteers;
  active_session public.attendance_sessions;
  actor uuid;
  token_fingerprint text;
  happened_at timestamptz := statement_timestamp();
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication is required';
  end if;

  if scan_event_credential_impl.scan_mode not in ('checkin', 'checkout') then
    raise exception 'Scan mode must be checkin or checkout';
  end if;

  select * into ev
  from public.events e
  where e.id = scan_event_credential_impl.event_id
    and private.has_org_role(e.organization_id, null);

  if ev.id is null then
    raise exception 'Event not found or access denied';
  end if;

  actor := private.current_profile_id();
  token_fingerprint := encode(
    extensions.digest(scan_event_credential_impl.secure_token, 'sha256'),
    'hex'
  );

  select r.* into reg
  from public.registrations r
  where r.event_id = ev.id
    and r.qr_token_hash = token_fingerprint
  limit 1;

  if reg.id is null then
    insert into public.scan_events(
      organization_id, event_id, result, device_session, raw_token_fingerprint
    ) values (
      ev.organization_id, ev.id, 'invalid', left(scan_event_credential_impl.device_session, 100), token_fingerprint
    );
    return query select 'invalid'::text, null::uuid, null::text, null::text,
      null::uuid, happened_at, 'This QR code is not registered for this opportunity.'::text;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(reg.id::text, 0));
  select * into volunteer from public.volunteers v where v.id = reg.volunteer_id;

  if reg.status <> 'registered' then
    insert into public.scan_events(
      organization_id, event_id, registration_id, result, device_session, raw_token_fingerprint
    ) values (
      ev.organization_id, ev.id, reg.id, 'blocked', left(scan_event_credential_impl.device_session, 100), token_fingerprint
    );
    return query select 'blocked'::text, reg.id, volunteer.first_name, volunteer.last_name,
      null::uuid, happened_at, 'This registration is not active.'::text;
    return;
  end if;

  select * into active_session
  from public.attendance_sessions s
  where s.event_id = ev.id
    and s.registration_id = reg.id
    and s.status = 'open'
    and s.checked_out_at is null
  order by s.checked_in_at desc
  limit 1
  for update;

  if scan_event_credential_impl.scan_mode = 'checkin' then
    if active_session.id is not null then
      insert into public.scan_events(
        organization_id, event_id, registration_id, result, device_session, raw_token_fingerprint
      ) values (
        ev.organization_id, ev.id, reg.id, 'duplicate_ignored', left(scan_event_credential_impl.device_session, 100), token_fingerprint
      );
      return query select 'already_checked_in'::text, reg.id, volunteer.first_name, volunteer.last_name,
        active_session.id, active_session.checked_in_at,
        (volunteer.first_name || ' ' || volunteer.last_name || ' is already checked in.')::text;
      return;
    end if;

    insert into public.attendance_sessions(
      organization_id, event_id, registration_id, checked_in_at,
      check_in_method, checked_in_by, status
    ) values (
      ev.organization_id, ev.id, reg.id, happened_at,
      'usb_qr_scanner', actor, 'open'
    ) returning id into attendance_session_id;

    insert into public.scan_events(
      organization_id, event_id, registration_id, result, device_session, raw_token_fingerprint
    ) values (
      ev.organization_id, ev.id, reg.id, 'checkin', left(scan_event_credential_impl.device_session, 100), token_fingerprint
    );

    return query select 'checked_in'::text, reg.id, volunteer.first_name, volunteer.last_name,
      attendance_session_id, happened_at,
      (volunteer.first_name || ' ' || volunteer.last_name || ' checked in.')::text;
    return;
  end if;

  if active_session.id is null then
    insert into public.scan_events(
      organization_id, event_id, registration_id, result, device_session, raw_token_fingerprint
    ) values (
      ev.organization_id, ev.id, reg.id, 'blocked', left(scan_event_credential_impl.device_session, 100), token_fingerprint
    );
    return query select 'not_checked_in'::text, reg.id, volunteer.first_name, volunteer.last_name,
      null::uuid, happened_at,
      (volunteer.first_name || ' ' || volunteer.last_name || ' is not currently checked in.')::text;
    return;
  end if;

  update public.attendance_sessions
  set checked_out_at = happened_at,
      check_out_method = 'usb_qr_scanner',
      checked_out_by = actor,
      status = 'closed'
  where id = active_session.id;

  insert into public.scan_events(
    organization_id, event_id, registration_id, result, device_session, raw_token_fingerprint
  ) values (
    ev.organization_id, ev.id, reg.id, 'checkout', left(scan_event_credential_impl.device_session, 100), token_fingerprint
  );

  return query select 'checked_out'::text, reg.id, volunteer.first_name, volunteer.last_name,
    active_session.id, happened_at,
    (volunteer.first_name || ' ' || volunteer.last_name || ' checked out.')::text;
end
$$;

revoke all on function private.scan_event_credential_impl(uuid,text,text,text) from public, anon, authenticated;
grant execute on function private.scan_event_credential_impl(uuid,text,text,text) to authenticated;

create or replace function public.scan_event_credential(
  event_id uuid,
  secure_token text,
  scan_mode text default 'checkin',
  device_session text default null
)
returns table (
  action text,
  registration_id uuid,
  volunteer_first_name text,
  volunteer_last_name text,
  attendance_session_id uuid,
  occurred_at timestamptz,
  message text
)
language sql
security invoker
set search_path = ''
as $$
  select * from private.scan_event_credential_impl(event_id, secure_token, scan_mode, device_session)
$$;

revoke all on function public.scan_event_credential(uuid,text,text,text) from public, anon;
grant execute on function public.scan_event_credential(uuid,text,text,text) to authenticated;
