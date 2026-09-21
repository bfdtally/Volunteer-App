create function private.handle_new_auth_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(auth_user_id, first_name, last_name, email)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'first_name'),''), split_part(coalesce(new.email,''),'@',1)),
    coalesce(nullif(trim(new.raw_user_meta_data->>'last_name'),''), ''),
    coalesce(new.email,'')
  ) on conflict (auth_user_id) do update set email=excluded.email, updated_at=now();
  return new;
end $$;
revoke all on function private.handle_new_auth_user() from public, anon, authenticated;

create trigger on_auth_user_created after insert or update of email on auth.users
for each row execute function private.handle_new_auth_user();

create function private.bootstrap_organization_impl(organization_name text, contact_email text default null)
returns table(organization_id uuid, profile_id uuid)
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  profile uuid;
  org uuid;
  base_slug text;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  select id into profile from public.profiles where auth_user_id=actor;
  if profile is null then
    insert into public.profiles(auth_user_id,first_name,last_name,email)
    select id,coalesce(nullif(trim(raw_user_meta_data->>'first_name'),''),split_part(coalesce(email,''),'@',1)),coalesce(nullif(trim(raw_user_meta_data->>'last_name'),''),''),coalesce(email,'')
    from auth.users where id=actor returning id into profile;
  end if;
  if exists(select 1 from public.organization_members where user_id=profile and status='active') then raise exception 'User already belongs to an organization'; end if;
  if nullif(trim(organization_name),'') is null then raise exception 'Organization name is required'; end if;
  base_slug:=trim(both '-' from regexp_replace(lower(trim(organization_name)),'[^a-z0-9]+','-','g'));
  insert into public.organizations(name,slug,contact_email)
  values(trim(organization_name),base_slug||'-'||substr(replace(gen_random_uuid()::text,'-',''),1,6),nullif(trim(contact_email),'')) returning id into org;
  insert into public.organization_members(organization_id,user_id,role,status) values(org,profile,'owner','active');
  return query select org,profile;
end $$;
revoke all on function private.bootstrap_organization_impl(text,text) from public,anon,authenticated;
grant execute on function private.bootstrap_organization_impl(text,text) to authenticated;

create function public.bootstrap_organization(organization_name text, contact_email text default null)
returns table(organization_id uuid, profile_id uuid)
language sql security invoker set search_path = '' as $$
  select * from private.bootstrap_organization_impl(organization_name,contact_email)
$$;
revoke all on function public.bootstrap_organization(text,text) from public,anon;
grant execute on function public.bootstrap_organization(text,text) to authenticated;

-- Backfill profiles for users created before the trigger existed.
insert into public.profiles(auth_user_id,first_name,last_name,email)
select u.id,coalesce(nullif(trim(u.raw_user_meta_data->>'first_name'),''),split_part(coalesce(u.email,''),'@',1)),coalesce(nullif(trim(u.raw_user_meta_data->>'last_name'),''),''),coalesce(u.email,'')
from auth.users u left join public.profiles p on p.auth_user_id=u.id where p.id is null;
