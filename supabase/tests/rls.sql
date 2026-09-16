begin;
select plan(5);
select has_table('public','organizations','organizations exists');
select has_table('public','audit_logs','audit log exists');
select is((select relrowsecurity from pg_class where oid='public.volunteers'::regclass),true,'volunteers have RLS');
select is((select relrowsecurity from pg_class where oid='public.registrations'::regclass),true,'registrations have RLS');
select is((select relrowsecurity from pg_class where oid='public.audit_logs'::regclass),true,'audit logs have RLS');
select * from finish();
rollback;
