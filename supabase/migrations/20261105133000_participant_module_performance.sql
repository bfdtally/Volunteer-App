-- Participant module performance follow-up: remove overlapping SELECT policies
-- and cover foreign keys used by roster, attendance, and organization queries.

drop policy if exists family_registrations_manager_all on public.family_registrations;
drop policy if exists participant_groups_manager_all on public.participant_groups;
drop policy if exists participants_manager_all on public.participants;
drop policy if exists participant_registrations_manager_all on public.participant_registrations;
drop policy if exists participant_attendance_staff_all on public.participant_attendance;

create policy family_registrations_manager_insert on public.family_registrations for insert to authenticated with check(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy family_registrations_manager_update on public.family_registrations for update to authenticated using(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[])) with check(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy family_registrations_manager_delete on public.family_registrations for delete to authenticated using(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy participant_groups_manager_insert on public.participant_groups for insert to authenticated with check(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy participant_groups_manager_update on public.participant_groups for update to authenticated using(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[])) with check(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy participant_groups_manager_delete on public.participant_groups for delete to authenticated using(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy participants_manager_insert on public.participants for insert to authenticated with check(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy participants_manager_update on public.participants for update to authenticated using(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[])) with check(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy participants_manager_delete on public.participants for delete to authenticated using(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy participant_registrations_manager_insert on public.participant_registrations for insert to authenticated with check(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy participant_registrations_manager_update on public.participant_registrations for update to authenticated using(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[])) with check(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy participant_registrations_manager_delete on public.participant_registrations for delete to authenticated using(private.has_org_role(organization_id,array['owner','administrator','event_coordinator']::public.member_role[]));
create policy participant_attendance_staff_insert on public.participant_attendance for insert to authenticated with check(private.has_org_role(organization_id,null));
create policy participant_attendance_staff_update on public.participant_attendance for update to authenticated using(private.has_org_role(organization_id,null)) with check(private.has_org_role(organization_id,null));
create policy participant_attendance_staff_delete on public.participant_attendance for delete to authenticated using(private.has_org_role(organization_id,array['owner','administrator']::public.member_role[]));

create index if not exists family_registrations_event_id_idx on public.family_registrations(event_id);
create index if not exists family_registrations_organization_id_idx on public.family_registrations(organization_id);
create index if not exists participant_groups_event_id_idx on public.participant_groups(event_id);
create index if not exists participant_groups_organization_id_idx on public.participant_groups(organization_id);
create index if not exists participant_registrations_organization_id_idx on public.participant_registrations(organization_id);
create index if not exists participant_registrations_participant_id_idx on public.participant_registrations(participant_id);
create index if not exists participant_attendance_organization_id_idx on public.participant_attendance(organization_id);
create index if not exists participant_attendance_checked_in_by_idx on public.participant_attendance(checked_in_by) where checked_in_by is not null;
create index if not exists participant_attendance_checked_out_by_idx on public.participant_attendance(checked_out_by) where checked_out_by is not null;
