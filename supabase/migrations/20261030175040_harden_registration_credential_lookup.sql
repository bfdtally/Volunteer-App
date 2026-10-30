create or replace function private.get_registration_credential_impl(secure_token text)
returns table (
  registration_id uuid,
  registration_status public.registration_status,
  volunteer_first_name text,
  volunteer_last_name text,
  event_name text,
  event_slug text,
  event_date date,
  event_start_time time,
  event_end_time time,
  event_location text,
  event_logo_url text,
  event_primary_color text,
  event_secondary_color text,
  selected_occurrences jsonb
)
language sql security definer set search_path = '' as $$
  select
    r.id, r.status, v.first_name, v.last_name,
    e.name, e.slug, e.date, e.start_time, e.end_time, e.location,
    e.logo_url, e.primary_color, e.secondary_color,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', eo.id, 'starts_at', eo.starts_at,
            'ends_at', eo.ends_at, 'location', eo.location
          ) order by eo.starts_at
        )
        from public.registration_occurrences ro
        join public.event_occurrences eo on eo.id = ro.occurrence_id
        where ro.registration_id = r.id
      ),
      '[]'::jsonb
    )
  from public.registrations r
  join public.volunteers v on v.id = r.volunteer_id
  join public.events e on e.id = r.event_id
  where r.qr_token_hash = encode(
    extensions.digest(get_registration_credential_impl.secure_token, 'sha256'),
    'hex'
  )
  limit 1
$$;

revoke all on function private.get_registration_credential_impl(text) from public;
grant execute on function private.get_registration_credential_impl(text) to anon, authenticated;

create or replace function public.get_registration_credential(secure_token text)
returns table (
  registration_id uuid,
  registration_status public.registration_status,
  volunteer_first_name text,
  volunteer_last_name text,
  event_name text,
  event_slug text,
  event_date date,
  event_start_time time,
  event_end_time time,
  event_location text,
  event_logo_url text,
  event_primary_color text,
  event_secondary_color text,
  selected_occurrences jsonb
)
language sql security invoker set search_path = '' as $$
  select * from private.get_registration_credential_impl(secure_token)
$$;

revoke all on function public.get_registration_credential(text) from public;
grant execute on function public.get_registration_credential(text) to anon, authenticated;
