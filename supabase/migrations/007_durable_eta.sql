-- GPS events and ETA work are committed together. Only leased workers can publish results.
alter table tracking_events add unique(tenant_id,id);
alter table vehicles add column gps_event_id uuid;
alter table vehicles add foreign key(tenant_id,gps_event_id) references tracking_events(tenant_id,id);
alter table eta_history add column source_event_id uuid;
alter table eta_history add column source_recorded_at timestamptz;
alter table eta_history add column route_version integer;
alter table eta_history add column stop_type text;
alter table eta_history add column valid_until timestamptz;
alter table eta_history add column approved_by uuid;
alter table eta_history add column approved_at timestamptz;
alter table eta_history add unique(tenant_id,id);
alter table eta_history add foreign key(tenant_id,source_event_id) references tracking_events(tenant_id,id);
alter table jobs add column current_eta_id uuid;
alter table jobs add column eta_state text not null default 'missing' check(eta_state in('missing','pending','fresh','unavailable','stale'));
alter table jobs add foreign key(tenant_id,current_eta_id) references eta_history(tenant_id,id);
create table tracking_work(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,job_id uuid not null,event_id uuid not null,
 route_version integer not null,stop_type text not null check(stop_type in('loading','delivery')),
 to_lat double precision not null,to_lng double precision not null,
 status text not null default 'pending' check(status in('pending','leased','done','failed','superseded')),
 attempts integer not null default 0,available_at timestamptz not null default now(),lease_until timestamptz,lease_token uuid,
 last_error text,created_at timestamptz not null default now(),finished_at timestamptz,
 unique(tenant_id,job_id,event_id,route_version),foreign key(tenant_id,job_id) references jobs(tenant_id,id),foreign key(tenant_id,event_id) references tracking_events(tenant_id,id)
);
alter table tracking_work enable row level security;
revoke all on tracking_work from anon,authenticated;
create index tracking_work_pending on tracking_work(status,available_at);
create function enqueue_job_eta(j uuid) returns void language plpgsql security definer set search_path=public as $$
declare job jobs;v vehicles;e tracking_events;target_lat float8;target_lng float8;stop text;
begin
 select * into job from jobs where id=j for update;
 if not found then return;end if;
 if job.status not in('En Route to Loading','At Loading','Loaded','In Transit','At Delivery') then
  update jobs set eta=null,current_eta_id=null,eta_approved=false,eta_state='missing' where id=j;return;
 end if;
 select * into v from vehicles where id=job.vehicle_id and tenant_id=job.tenant_id;
 select * into e from tracking_events where id=v.gps_event_id and tenant_id=v.tenant_id;
 if e.id is null or e.recorded_at<now()-interval '30 minutes' then
  update jobs set eta=null,current_eta_id=null,eta_approved=false,eta_state='missing' where id=j;return;
 end if;
 if job.status in('En Route to Loading','At Loading') then target_lat:=job.loading_lat;target_lng:=job.loading_lng;stop:='loading';
 else target_lat:=job.destination_lat;target_lng:=job.destination_lng;stop:='delivery';end if;
 if target_lat is null or target_lng is null then update jobs set eta=null,current_eta_id=null,eta_approved=false,eta_state='unavailable' where id=j;return;end if;
 insert into tracking_work(tenant_id,job_id,event_id,route_version,stop_type,to_lat,to_lng) values(job.tenant_id,j,e.id,job.route_version,stop,target_lat,target_lng) on conflict do nothing;
 update jobs set eta=null,current_eta_id=null,eta_approved=false,eta_state='pending' where id=j;
end $$;
create function queue_after_dispatch() returns trigger language plpgsql security definer set search_path=public as $$ begin perform enqueue_job_eta(new.id);return new;end $$;
create trigger queue_after_dispatch after update of status,loading_lat,loading_lng,destination_lat,destination_lng,vehicle_id on jobs for each row execute function queue_after_dispatch();
create or replace function ingest_gps(payload jsonb) returns boolean language plpgsql security definer set search_path=public as $$
declare v vehicles;inserted integer;gps_id uuid;j record;at timestamptz:=(payload->>'recorded_at')::timestamptz;
begin
 if at>now()+interval '1 minute' or at<now()-interval '1 day' then raise exception using errcode='23514',message='GPS timestamp outside accepted window';end if;
 select * into v from vehicles where id=(payload->>'vehicle_id')::uuid and tenant_id=(payload->>'tenant_id')::uuid for update;
 if not found then raise exception using errcode='42501',message='Vehicle unavailable';end if;
 if v.provider<>payload->>'provider' and not(v.simulated and payload->>'provider'='Simulator') then raise exception 'Provider mismatch';end if;
 insert into tracking_events(tenant_id,vehicle_id,provider,event_id,lat,lng,speed,recorded_at)
 values(v.tenant_id,v.id,payload->>'provider',payload->>'event_id',(payload->>'lat')::float8,(payload->>'lng')::float8,(payload->>'speed')::float8,at) on conflict do nothing returning id into gps_id;
 get diagnostics inserted=row_count;
 if inserted=0 or (v.gps_at is not null and v.gps_at>=at) then return false;end if;
 update vehicles set lat=(payload->>'lat')::float8,lng=(payload->>'lng')::float8,speed=(payload->>'speed')::float8,gps_at=at,gps_event_id=gps_id,simulated=(payload->>'provider'='Simulator'),location='GPS '||(payload->>'lat')||', '||(payload->>'lng') where id=v.id;
 for j in select id from jobs where tenant_id=v.tenant_id and vehicle_id=v.id and status in('En Route to Loading','At Loading','Loaded','In Transit','At Delivery') loop perform enqueue_job_eta(j.id);end loop;
 return true;
end $$;
create function claim_eta_work(batch_size integer default 5) returns table(id uuid,lease_token uuid,from_lat float8,from_lng float8,recorded_at timestamptz,to_lat float8,to_lng float8) language plpgsql security definer set search_path=public as $$
begin
 update tracking_work w set status='failed',last_error='Lease expired after maximum attempts',finished_at=now() where w.status='leased' and w.lease_until<now() and w.attempts>=5;
 update jobs j set eta_state='unavailable' from tracking_work w join tracking_events e on e.id=w.event_id join vehicles v on v.id=e.vehicle_id where w.status='failed' and j.id=w.job_id and j.route_version=w.route_version and j.current_eta_id is null and v.gps_event_id=e.id;
 return query with candidates as (
  select w.id from tracking_work w where (w.status='pending' and w.available_at<=now() or w.status='leased' and w.lease_until<now()) and w.attempts<5 order by w.created_at for update skip locked limit least(greatest(batch_size,1),10)
 ), claimed as (
  update tracking_work w set status='leased',lease_until=now()+interval '60 seconds',lease_token=gen_random_uuid(),attempts=w.attempts+1 from candidates c where w.id=c.id returning w.*
 ) select c.id,c.lease_token,e.lat,e.lng,e.recorded_at,c.to_lat,c.to_lng from claimed c join tracking_events e on e.id=c.event_id and e.tenant_id=c.tenant_id;
end $$;
create function finish_eta_work(work_id uuid,token uuid,new_eta timestamptz,route_provider text) returns boolean language plpgsql security definer set search_path=public as $$
declare w tracking_work;j jobs;e tracking_events;v vehicles;estimate uuid;
begin
 select * into w from tracking_work where id=work_id for update;
 if not found or w.status<>'leased' or w.lease_token is distinct from token or w.lease_until<now() then raise exception using errcode='40001',message='ETA lease expired';end if;
 select * into j from jobs where id=w.job_id and tenant_id=w.tenant_id for update;
 select * into e from tracking_events where id=w.event_id and tenant_id=w.tenant_id;
 select * into v from vehicles where id=j.vehicle_id and tenant_id=w.tenant_id;
 if j.route_version<>w.route_version or v.gps_event_id is distinct from e.id or j.status not in('En Route to Loading','At Loading','Loaded','In Transit','At Delivery') or e.recorded_at<now()-interval '30 minutes' then
  update tracking_work set status='superseded',finished_at=now() where id=work_id;return false;
 end if;
 if new_eta is null or route_provider is null then raise exception using errcode='23514',message='Routing result required';end if;
 insert into eta_history(tenant_id,job_id,eta,provider,source_event_id,source_recorded_at,route_version,stop_type,valid_until)
 values(w.tenant_id,j.id,new_eta,route_provider,e.id,e.recorded_at,w.route_version,w.stop_type,least(now()+interval '15 minutes',e.recorded_at+interval '30 minutes')) returning id into estimate;
 update jobs set eta=new_eta,current_eta_id=estimate,eta_state='fresh',eta_approved=false where id=j.id;
 update tracking_work set status='done',finished_at=now(),last_error=null where id=work_id;return true;
end $$;
create function fail_eta_work(work_id uuid,token uuid,error_code text) returns void language plpgsql security definer set search_path=public as $$
declare w tracking_work;
begin
 select * into w from tracking_work where id=work_id for update;
 if not found or w.status<>'leased' or w.lease_token is distinct from token then raise exception using errcode='40001',message='ETA lease changed';end if;
 update tracking_work set status=case when attempts>=5 then 'failed' else 'pending' end,available_at=now()+make_interval(secs=>least(300,15*(2^attempts)::int)),lease_until=null,last_error=left(error_code,100),finished_at=case when attempts>=5 then now() else null end where id=work_id;
 update jobs set eta_state='unavailable' where id=w.job_id and route_version=w.route_version and current_eta_id is null and exists(select 1 from vehicles v join tracking_events e on e.vehicle_id=v.id and e.tenant_id=v.tenant_id where e.id=w.event_id and v.gps_event_id=e.id);
end $$;
create function approve_eta(t uuid,j uuid,expected_eta_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare job jobs;e eta_history;v vehicles;
begin
 if not has_tenant(t,true,true) then raise exception using errcode='42501',message='Forbidden';end if;
 select * into job from jobs where tenant_id=t and id=j for update;
 if not found then raise exception using errcode='P0002',message='Job not found';end if;
 if job.current_eta_id is distinct from expected_eta_id or job.eta_state<>'fresh' then raise exception using errcode='40001',message='ETA changed; review the current estimate';end if;
 select * into e from eta_history where tenant_id=t and id=expected_eta_id;
 select * into v from vehicles where tenant_id=t and id=job.vehicle_id;
 if e.valid_until<=now() or v.gps_event_id is distinct from e.source_event_id or job.route_version<>e.route_version then raise exception using errcode='40001',message='ETA is stale';end if;
 update eta_history set approved_by=auth.uid(),approved_at=now() where id=e.id;
 update jobs set eta_approved=true where id=j;
end $$;
drop function approved_etas();
create function approved_etas() returns table(job_id uuid,eta timestamptz,eta_id uuid,eta_state text,eta_source_at timestamptz,eta_valid_until timestamptz,eta_stop text) language sql stable security definer set search_path=public as $$
 select j.id,
 case when j.eta_state='fresh' and e.valid_until>now() and v.gps_event_id=e.source_event_id and j.route_version=e.route_version and (j.eta_approved or has_tenant(j.tenant_id,false,true)) then e.eta else null end,
 case when has_tenant(j.tenant_id,false,true) then e.id else null end,
 case when j.eta_state='fresh' and (e.valid_until<=now() or v.gps_event_id is distinct from e.source_event_id) then 'stale' when j.eta_state='fresh' and not j.eta_approved and not has_tenant(j.tenant_id,false,true) then 'awaiting approval' else j.eta_state end,
 e.source_recorded_at,e.valid_until,e.stop_type
 from jobs j join vehicles v on v.id=j.vehicle_id and v.tenant_id=j.tenant_id left join eta_history e on e.id=j.current_eta_id and e.tenant_id=j.tenant_id where has_tenant(j.tenant_id);
$$;
revoke all on function enqueue_job_eta(uuid),queue_after_dispatch(),claim_eta_work(integer),finish_eta_work(uuid,uuid,timestamptz,text),fail_eta_work(uuid,uuid,text),approve_eta(uuid,uuid,uuid),approved_etas() from public;
grant execute on function claim_eta_work(integer),finish_eta_work(uuid,uuid,timestamptz,text),fail_eta_work(uuid,uuid,text) to service_role;
grant execute on function approve_eta(uuid,uuid,uuid),approved_etas() to authenticated;
-- Remove the unfenced legacy write path.
drop function record_eta(uuid,uuid,timestamptz,text);
grant select on visible_jobs to authenticated;
