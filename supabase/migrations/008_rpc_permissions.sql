-- Supabase grants function execution to API roles through default privileges.
-- Revoking PUBLIC alone is insufficient: explicitly remove the API-role grants.
revoke all on function enqueue_job_eta(uuid),queue_after_dispatch(),claim_eta_work(integer),finish_eta_work(uuid,uuid,timestamptz,text),fail_eta_work(uuid,uuid,text) from public,anon,authenticated;
grant execute on function claim_eta_work(integer),finish_eta_work(uuid,uuid,timestamptz,text),fail_eta_work(uuid,uuid,text) to service_role;
