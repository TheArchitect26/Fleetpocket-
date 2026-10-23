-- Operational commands own state transitions; public clients cannot write telemetry.
alter table jobs add column version integer not null default 1;
alter table jobs add column previous_status text;
alter table jobs add column loading_lat double precision check(loading_lat between -90 and 90);
alter table jobs add column loading_lng double precision check(loading_lng between -180 and 180);
alter table jobs add column route_version integer not null default 1;
alter table audit add column before_record jsonb;
alter table audit add column after_record jsonb;
drop policy tenant_read on audit;
create policy audit_controller_read on audit for select to authenticated using(has_tenant(tenant_id,false,true));
create or replace function audit_change() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into audit(tenant_id,entity_id,action,actor,before_record,after_record)
 values(new.tenant_id,new.id,TG_TABLE_NAME||' '||lower(TG_OP),coalesce(auth.uid()::text,'worker'),case when TG_OP='UPDATE' then to_jsonb(old) else null end,to_jsonb(new));
 return new;
end $$;
create function immutable_tenant() returns trigger language plpgsql set search_path=public as $$
begin if new.tenant_id<>old.tenant_id then raise exception using errcode='42501',message='Tenant ownership is immutable';end if;return new;end $$;
do $$ declare t text;begin foreach t in array array['drivers','vehicles','jobs','documents','alerts','updates','tracking_events','eta_history'] loop
 execute format('create trigger immutable_tenant before update on %I for each row execute function immutable_tenant()',t);
end loop;end $$;
revoke insert,update,delete on vehicles from authenticated;
grant insert(id,tenant_id,fleet_no,horse_reg,trailer_one,trailer_two,driver_id,group_name) on vehicles to authenticated;
grant update(fleet_no,horse_reg,trailer_one,trailer_two,driver_id,group_name) on vehicles to authenticated;
revoke insert,update,delete on jobs from authenticated;
-- Fail migration on conflicting live assignments; operators must reconcile existing data explicitly.
create unique index one_live_assignment on jobs(tenant_id,vehicle_id)
 where status in('Assigned','Accepted','En Route to Loading','At Loading','Loaded','In Transit','At Delivery','Exception');
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
  new.route_version:=old.route_version+1;
 end if;
 if (new.loading_lat,new.loading_lng,new.destination_lat,new.destination_lng,new.vehicle_id) is distinct from (old.loading_lat,old.loading_lng,old.destination_lat,old.destination_lng,old.vehicle_id) then
  new.route_version:=old.route_version+1;new.version:=old.version+1;
 end if;
 return new;
end $$;
create function synchronize_load() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status in('Loaded','In Transit','At Delivery') then update vehicles set load_status='Loaded' where id=new.vehicle_id and tenant_id=new.tenant_id;
 elsif new.status in('Delivered','POD Received','Closed') then update vehicles set load_status='Empty' where id=new.vehicle_id and tenant_id=new.tenant_id;end if;
 return new;
end $$;
create trigger synchronize_load after update of status on jobs for each row execute function synchronize_load();
create function create_transport_job(payload jsonb) returns uuid language plpgsql security definer set search_path=public as $$
declare t uuid:=(payload->>'tenant_id')::uuid;v vehicles;j uuid;
begin
 if not has_tenant(t,true) then raise exception using errcode='42501',message='Forbidden';end if;
 select * into v from vehicles where tenant_id=t and id=(payload->>'vehicle_id')::uuid;
 if not found then raise exception using errcode='42501',message='Vehicle unavailable';end if;
 if length(payload->>'cargo') not between 2 and 200 or length(payload->>'loading_customer') not between 2 and 100 or length(payload->>'delivery_customer') not between 2 and 100
 or length(payload->>'loading_code') not between 2 and 12 or length(payload->>'delivery_code') not between 2 and 12 then raise exception using errcode='23514',message='Invalid job fields';end if;
 insert into jobs(tenant_id,vehicle_id,driver_id,loading_code,loading_customer,delivery_code,delivery_customer,cargo,scheduled_at,destination_lat,destination_lng,loading_lat,loading_lng)
 values(t,v.id,v.driver_id,payload->>'loading_code',payload->>'loading_customer',payload->>'delivery_code',payload->>'delivery_customer',payload->>'cargo',(payload->>'scheduled_at')::timestamptz,(payload->>'destination_lat')::float8,(payload->>'destination_lng')::float8,(payload->>'loading_lat')::float8,(payload->>'loading_lng')::float8) returning id into j;
 return j;
end $$;
alter table jobs add constraint destination_lat_valid check(destination_lat between -90 and 90);
alter table jobs add constraint destination_lng_valid check(destination_lng between -180 and 180);
create function dispatch_job(t uuid,j uuid,expected_version integer,next_status text,reason text default null) returns integer language plpgsql security definer set search_path=public as $$
declare current jobs;result integer;
begin
 if not has_tenant(t,true,true) then raise exception using errcode='42501',message='Forbidden';end if;
 select * into current from jobs where tenant_id=t and id=j;
 if not found then raise exception using errcode='P0002',message='Job not found';end if;
 perform 1 from vehicles where tenant_id=t and id=current.vehicle_id for update;
 select * into current from jobs where tenant_id=t and id=j for update;
 if not found then raise exception using errcode='P0002',message='Job not found';end if;
 if current.version<>expected_version then raise exception using errcode='40001',message='Job changed; refresh before continuing';end if;
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
revoke all on function create_transport_job(jsonb),dispatch_job(uuid,uuid,integer,text,text) from public;
grant execute on function create_transport_job(jsonb),dispatch_job(uuid,uuid,integer,text,text) to authenticated;
-- Secure, explicit document publication. Customer uploaders can review their own uploads.
alter table documents add column released boolean not null default false;
alter table documents add column uploaded_by uuid default auth.uid();
alter table documents add column verified_by uuid;
alter table documents add column verified_at timestamptz;
revoke insert,update,delete on documents from authenticated;
grant insert(tenant_id,name,kind,vehicle_id,job_id,driver_id,expires_at,path) on documents to authenticated;
drop policy tenant_read on documents;
create policy document_read on documents for select to authenticated using(has_tenant(tenant_id) and
 (has_tenant(tenant_id,false,true) or (uploaded_by=auth.uid() and has_tenant(tenant_id,true)) or (released and verified and kind in('Proof of delivery','Delivery instructions','Loading document'))));
create function can_read_document_object(object_name text) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from documents d where d.path=object_name and has_tenant(d.tenant_id) and
 (has_tenant(d.tenant_id,false,true) or (d.uploaded_by=auth.uid() and has_tenant(d.tenant_id,true)) or (d.released and d.verified and d.kind in('Proof of delivery','Delivery instructions','Loading document'))));
$$;
revoke all on function can_read_document_object(text) from public;grant execute on function can_read_document_object(text) to authenticated;
drop policy doc_download on storage.objects;
create policy doc_download on storage.objects for select to authenticated using(bucket_id='fleet-documents' and can_read_document_object(name));
create function guard_document_evidence() returns trigger language plpgsql set search_path=public as $$
begin
 if TG_OP='UPDATE' and (new.path,new.kind,new.vehicle_id,new.job_id,new.uploaded_by) is distinct from (old.path,old.kind,old.vehicle_id,old.job_id,old.uploaded_by) then raise exception using errcode='23514',message='Document evidence is immutable; upload a new version';end if;
 if new.kind='Proof of delivery' and (new.job_id is null or not exists(select 1 from jobs where id=new.job_id and tenant_id=new.tenant_id and vehicle_id=new.vehicle_id)) then raise exception using errcode='23514',message='POD must match its job and vehicle';end if;
 return new;
end $$;
create trigger guard_document_evidence before insert or update on documents for each row execute function guard_document_evidence();
create function verify_document(t uuid,d uuid,release_to_customer boolean default false) returns void language plpgsql security definer set search_path=public as $$
declare doc documents;
begin
 if not has_tenant(t,true,true) then raise exception using errcode='42501',message='Forbidden';end if;
 select * into doc from documents where tenant_id=t and id=d for update;
 if not found then raise exception using errcode='P0002',message='Document not found';end if;
 if not exists(select 1 from storage.objects where bucket_id='fleet-documents' and name=doc.path) then raise exception using errcode='23514',message='Stored file required for verification';end if;
 if release_to_customer and doc.kind not in('Proof of delivery','Delivery instructions','Loading document') then raise exception using errcode='23514',message='This document type cannot be customer released';end if;
 update documents set verified=true,verified_by=coalesce(verified_by,auth.uid()),verified_at=coalesce(verified_at,now()),released=release_to_customer where id=d;
end $$;
revoke all on function verify_document(uuid,uuid,boolean) from public;grant execute on function verify_document(uuid,uuid,boolean) to authenticated;
-- Expose workflow versions without publishing raw estimates.
drop view visible_jobs;
grant select(version,previous_status,loading_lat,loading_lng,route_version) on jobs to authenticated;
create view visible_jobs with(security_invoker=true) as select id,tenant_id,reference,vehicle_id,driver_id,controller,loading_code,loading_customer,delivery_code,delivery_customer,cargo,status,scheduled_at,destination_lat,destination_lng,exception,eta_approved,version,previous_status,loading_lat,loading_lng,route_version from jobs;
