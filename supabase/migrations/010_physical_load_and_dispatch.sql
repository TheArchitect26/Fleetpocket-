-- Paperwork cannot unload a vehicle now carrying another job.
create or replace function synchronize_load() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status is not distinct from old.status then return new;end if;
 if new.status in('Loaded','In Transit','At Delivery') then
  update vehicles set load_status='Loaded' where id=new.vehicle_id and tenant_id=new.tenant_id;
 elsif new.status='Delivered' then
  update vehicles set load_status='Empty' where id=new.vehicle_id and tenant_id=new.tenant_id;
 end if;
 return new;
end $$;
-- Operational versions change with stage; route versions change with destination/stop.
create function job_stop(stage text) returns text language sql immutable set search_path=public as $$
 select case when stage in('En Route to Loading','At Loading') then 'loading' when stage in('Loaded','In Transit','At Delivery') then 'delivery' else null end;
$$;
revoke all on function job_stop(text) from public,anon;grant execute on function job_stop(text) to authenticated,service_role;
create or replace function validate_job_transition() returns trigger language plpgsql set search_path=public as $$
declare lifecycle text[]:=array['Created','Assigned','Accepted','En Route to Loading','At Loading','Loaded','In Transit','At Delivery','Delivered','POD Received','Closed'];
begin
 if new.status<>old.status then
  if old.status in('Closed','Cancelled') then raise exception using errcode='23514',message='Terminal job';end if;
  if old.status='Exception' then
   if new.status is distinct from old.previous_status or new.exception is not null then raise exception using errcode='23514',message='Resolve to the interrupted stage';end if;
  elsif new.status='Exception' then
   if nullif(trim(new.exception),'') is null then raise exception using errcode='23514',message='Exception reason required';end if;
   new.previous_status:=old.status;
  elsif new.status='Cancelled' then
   if old.status in('Loaded','In Transit','At Delivery') then raise exception using errcode='23514',message='Loaded work requires an exception and cargo recovery';end if;
  elsif array_position(lifecycle,new.status) is distinct from array_position(lifecycle,old.status)+1 then
   raise exception using errcode='23514',message='Advance one stage at a time';
  end if;
  if new.status in('POD Received','Closed') and not exists(select 1 from documents where tenant_id=new.tenant_id and job_id=new.id and vehicle_id=new.vehicle_id and kind='Proof of delivery' and verified) then
   raise exception using errcode='23514',message='Verified POD for this job and vehicle required';
  end if;
  new.version:=old.version+1;
 end if;
 if job_stop(new.status) is distinct from job_stop(old.status) or (new.loading_lat,new.loading_lng,new.destination_lat,new.destination_lng,new.vehicle_id) is distinct from (old.loading_lat,old.loading_lng,old.destination_lat,old.destination_lng,old.vehicle_id) then
  new.route_version:=old.route_version+1;
  if new.status=old.status then new.version:=old.version+1;end if;
 end if;
 return new;
end $$;
create or replace function dispatch_job(t uuid,j uuid,expected_version integer,next_status text,reason text default null) returns integer language plpgsql security definer set search_path=public as $$
declare current jobs;result integer;
begin
 if not has_tenant(t,true,true) then raise exception using errcode='42501',message='Forbidden';end if;
 select * into current from jobs where tenant_id=t and id=j;
 if not found then raise exception using errcode='P0002',message='Job not found';end if;
 perform 1 from vehicles where tenant_id=t and id=current.vehicle_id for update;
 select * into current from jobs where tenant_id=t and id=j for update;
 if not found then raise exception using errcode='P0002',message='Job not found';end if;
 if expected_version is null or current.version<>expected_version then raise exception using errcode='40001',message='Job changed; refresh before continuing';end if;
 -- A valid no-op has no UPDATE, audit event, load mutation or ETA invalidation.
 if next_status=current.status then return current.version;end if;
 if next_status='Exception' and (reason is null or length(trim(reason)) not between 3 and 1000) then raise exception using errcode='23514',message='Provide an exception reason';end if;
 if next_status='Resolve' then
  if current.status<>'Exception' then raise exception using errcode='23514',message='No exception to resolve';end if;
  if reason is null or length(trim(reason)) not between 3 and 1000 then raise exception using errcode='23514',message='Provide a resolution note';end if;
  update jobs set status=current.previous_status,exception=null where id=j returning version into result;
  insert into audit(tenant_id,entity_id,action,actor) values(t,j,'Exception resolved: '||reason,auth.uid()::text);
 else
  update jobs set status=next_status,exception=case when next_status='Exception' then reason else exception end,controller=case when next_status='Assigned' then auth.uid()::text else controller end where id=j returning version into result;
 end if;
 return result;
end $$;
-- Updating a column to its existing value does not invalidate a route.
create or replace function queue_after_dispatch() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.route_version<>old.route_version then perform enqueue_job_eta(new.id);end if;
 return new;
end $$;
