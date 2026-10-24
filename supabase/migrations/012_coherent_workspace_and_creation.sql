-- Every workspace field uses one SQL statement/snapshot with the caller's RLS.
create function workspace_snapshot() returns jsonb language sql stable security invoker set search_path=public as $$
 with
 ts as materialized(select * from tenants order by id limit 1001),
 vs as materialized(select * from vehicles order by fleet_no,id limit 1001),
 ds as materialized(select * from drivers order by name,id limit 1001),
 js as materialized(select j.id,case when j.status in('Assigned','Accepted','En Route to Loading','At Loading','Loaded','In Transit','At Delivery','Exception') then 0 when j.status='Created' then 1 else 2 end as priority,
  to_jsonb(j)||coalesce(to_jsonb(e)-'job_id','{}'::jsonb)||jsonb_build_object('eta',coalesce(to_jsonb(e.eta),'""'::jsonb)) as payload from visible_jobs j left join approved_etas() e on e.job_id=j.id order by priority,j.id limit 1001),
 docs as materialized(select * from documents order by created_at desc,id desc limit 1001),
 als as materialized(select * from alerts order by created_at desc,id desc limit 1001),
 aus as materialized(select * from audit order by created_at desc,id desc limit 1001),
 ups as materialized(select * from updates order by created_at desc,id desc limit 1001),
 ms as materialized(select tenant_id,role from memberships where user_id=auth.uid())
 select jsonb_build_object(
 'demo',false,'synced_at',now(),
 'tenants',(select coalesce(jsonb_agg(x order by x.id),'[]'::jsonb) from(select * from ts limit 1000)x),
 'vehicles',(select coalesce(jsonb_agg(x order by x.fleet_no,x.id),'[]'::jsonb) from(select * from vs limit 1000)x),
 'drivers',(select coalesce(jsonb_agg(x order by x.name,x.id),'[]'::jsonb) from(select * from ds limit 1000)x),
 'jobs',(select coalesce(jsonb_agg(x.payload order by x.priority,x.id),'[]'::jsonb) from(select * from js limit 1000)x),
 'documents',(select coalesce(jsonb_agg(x order by x.created_at desc,x.id desc),'[]'::jsonb) from(select * from docs limit 1000)x),
 'alerts',(select coalesce(jsonb_agg(x order by x.created_at desc,x.id desc),'[]'::jsonb) from(select * from als limit 1000)x),
 'audit',(select coalesce(jsonb_agg(x order by x.created_at desc,x.id desc),'[]'::jsonb) from(select * from aus limit 1000)x),
 'updates',(select coalesce(jsonb_agg(x order by x.created_at desc,x.id desc),'[]'::jsonb) from(select * from ups limit 1000)x),
 'capabilities',(select coalesce(jsonb_object_agg(tenant_id,role),'{}'::jsonb) from ms),
 'role',case when exists(select 1 from ms where role='admin') then 'admin' when exists(select 1 from ms where role='controller') then 'controller' when exists(select 1 from ms where role='customer_admin') then 'customer_admin' else 'customer_viewer' end,
 'truncated',(select coalesce(jsonb_agg(name),'[]'::jsonb) from(values('tenants',(select count(*) from ts)),('vehicles',(select count(*) from vs)),('drivers',(select count(*) from ds)),('jobs',(select count(*) from js)),('documents',(select count(*) from docs)),('alerts',(select count(*) from als)),('audit',(select count(*) from aus)),('updates',(select count(*) from ups))) as sizes(name,n) where n>1000)
 );
$$;
revoke all on function workspace_snapshot() from public,anon,authenticated;grant execute on function workspace_snapshot() to authenticated;
alter table jobs add column request_key uuid;
alter table jobs add column request_fingerprint jsonb;
alter table jobs add constraint jobs_request_key unique(tenant_id,request_key);
create or replace function create_transport_job(payload jsonb) returns uuid language plpgsql security definer set search_path=public as $$
declare t uuid:=(payload->>'tenant_id')::uuid;key uuid:=(payload->>'idempotency_key')::uuid;fingerprint jsonb;existing jobs;v vehicles;j uuid;
begin
 if not has_tenant(t,true) then raise exception using errcode='42501',message='Forbidden';end if;
 if key is null then raise exception using errcode='23514',message='Idempotency key required';end if;
 if coalesce(length(payload->>'cargo'),0) not between 2 and 200 or coalesce(length(payload->>'loading_customer'),0) not between 2 and 100 or coalesce(length(payload->>'delivery_customer'),0) not between 2 and 100
 or coalesce(length(payload->>'loading_code'),0) not between 2 and 12 or coalesce(length(payload->>'delivery_code'),0) not between 2 and 12 or payload->>'loading_lat' is null or payload->>'loading_lng' is null then
  raise exception using errcode='23514',message='Complete loading, delivery and cargo fields required';
 end if;
 fingerprint:=jsonb_build_object('vehicle_id',(payload->>'vehicle_id')::uuid,'loading_code',payload->>'loading_code','loading_customer',payload->>'loading_customer','delivery_code',payload->>'delivery_code','delivery_customer',payload->>'delivery_customer','cargo',payload->>'cargo','scheduled_at',(payload->>'scheduled_at')::timestamptz,'loading_lat',(payload->>'loading_lat')::float8,'loading_lng',(payload->>'loading_lng')::float8,'destination_lat',(payload->>'destination_lat')::float8,'destination_lng',(payload->>'destination_lng')::float8);
 select * into existing from jobs where tenant_id=t and request_key=key;
 if found then
  if existing.request_fingerprint is distinct from fingerprint then raise exception using errcode='40001',message='Request key already used for a different job';end if;
  return existing.id;
 end if;
 select * into v from vehicles where tenant_id=t and id=(payload->>'vehicle_id')::uuid;
 if not found then raise exception using errcode='42501',message='Vehicle unavailable';end if;
 insert into jobs(tenant_id,vehicle_id,driver_id,loading_code,loading_customer,delivery_code,delivery_customer,cargo,scheduled_at,destination_lat,destination_lng,loading_lat,loading_lng,request_key,request_fingerprint)
 values(t,v.id,v.driver_id,payload->>'loading_code',payload->>'loading_customer',payload->>'delivery_code',payload->>'delivery_customer',payload->>'cargo',(payload->>'scheduled_at')::timestamptz,(payload->>'destination_lat')::float8,(payload->>'destination_lng')::float8,(payload->>'loading_lat')::float8,(payload->>'loading_lng')::float8,key,fingerprint)
 on conflict on constraint jobs_request_key do nothing returning id into j;
 if j is not null then return j;end if;
 select * into existing from jobs where tenant_id=t and request_key=key;
 if existing.request_fingerprint is distinct from fingerprint then raise exception using errcode='40001',message='Request key already used for a different job';end if;
 return existing.id;
end $$;
