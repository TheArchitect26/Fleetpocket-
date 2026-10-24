-- Keep all GPS history, but only the latest unleased ETA work per job.
alter table jobs add column published_eta_id uuid;
alter table jobs add column eta_next_calculation_at timestamptz not null default '-infinity';
alter table jobs add foreign key(tenant_id,published_eta_id) references eta_history(tenant_id,id);
update jobs set published_eta_id=current_eta_id where eta_approved;
-- Rollout fences old worker leases. Pause workers/ingestion during migration.
update tracking_work set status='superseded',finished_at=now(),last_error='Worker policy upgraded' where status='leased';
with ranked as(select id,row_number() over(partition by tenant_id,job_id order by created_at desc,id desc) as n from tracking_work where status='pending')
 update tracking_work w set status='superseded',finished_at=now() from ranked r where w.id=r.id and r.n>1;
do $$ declare c record;begin for c in select conname from pg_constraint where conrelid='tracking_work'::regclass and contype='u' loop execute format('alter table tracking_work drop constraint %I',c.conname);end loop;end $$;
create unique index tracking_one_pending on tracking_work(tenant_id,job_id) where status='pending';
create unique index tracking_one_lease on tracking_work(tenant_id,job_id) where status='leased';
create index tracking_tenant_status on tracking_work(tenant_id,status,available_at);
create or replace function enqueue_job_eta(j uuid) returns void language plpgsql security definer set search_path=public as $$
declare job jobs;v vehicles;e tracking_events;latest eta_history;published eta_history;target_lat float8;target_lng float8;stop text;
begin
 select * into job from jobs where id=j for update;if not found then return;end if;
 stop:=job_stop(job.status);
 if stop is null then
  update tracking_work set status='superseded',finished_at=now() where job_id=j and status='pending';
  update jobs set eta=null,current_eta_id=null,published_eta_id=null,eta_approved=false,eta_state='missing' where id=j;return;
 end if;
 select * into v from vehicles where id=job.vehicle_id and tenant_id=job.tenant_id;
 select * into e from tracking_events where id=v.gps_event_id and tenant_id=v.tenant_id;
 select * into published from eta_history where id=job.published_eta_id and tenant_id=job.tenant_id;
 if published.id is not null and (published.route_version<>job.route_version or published.stop_type<>stop or published.valid_until<=now()) then
  update jobs set published_eta_id=null where id=j;
 end if;
 if e.id is null or e.recorded_at<now()-interval '2 minutes' then
  update tracking_work set status='superseded',finished_at=now() where job_id=j and status='pending';
  update jobs set eta_state='missing' where id=j;return;
 end if;
 select * into latest from eta_history where id=job.current_eta_id and tenant_id=job.tenant_id;
 -- Reusing the same completed source must preserve its result and approval.
 if latest.source_event_id=e.id and latest.route_version=job.route_version and latest.valid_until>now() then return;end if;
 if stop='loading' then target_lat:=job.loading_lat;target_lng:=job.loading_lng;else target_lat:=job.destination_lat;target_lng:=job.destination_lng;end if;
 if target_lat is null or target_lng is null then update jobs set eta_state='unavailable',published_eta_id=null where id=j;return;end if;
 insert into tracking_work(tenant_id,job_id,event_id,route_version,stop_type,to_lat,to_lng,available_at)
 values(job.tenant_id,j,e.id,job.route_version,stop,target_lat,target_lng,greatest(now(),job.eta_next_calculation_at))
 on conflict(tenant_id,job_id) where status='pending' do update set
 event_id=excluded.event_id,route_version=excluded.route_version,stop_type=excluded.stop_type,to_lat=excluded.to_lat,to_lng=excluded.to_lng,
 available_at=case when tracking_work.route_version<>excluded.route_version then excluded.available_at else greatest(tracking_work.available_at,excluded.available_at) end,
 attempts=case when tracking_work.route_version<>excluded.route_version then 0 else tracking_work.attempts end;
 update jobs set eta_state='pending',eta_approved=false where id=j;
end $$;
create or replace function claim_eta_work(batch_size integer default 5) returns table(id uuid,lease_token uuid,from_lat float8,from_lng float8,recorded_at timestamptz,to_lat float8,to_lng float8) language plpgsql security definer set search_path=public as $$
begin
 -- Discard obsolete inputs before spending provider capacity.
 update tracking_work w set status='superseded',finished_at=now() from jobs j,vehicles v,tracking_events e
 where w.job_id=j.id and v.id=j.vehicle_id and e.id=w.event_id and w.status='pending'
 and (j.route_version<>w.route_version or job_stop(j.status) is distinct from w.stop_type or v.gps_event_id<>e.id or e.recorded_at<now()-interval '2 minutes');
 update tracking_work w set status='superseded',finished_at=now() where w.status='leased' and w.lease_until<now() and exists(select 1 from tracking_work p where p.job_id=w.job_id and p.status='pending');
 update tracking_work w set status='superseded',finished_at=now() from jobs j,tracking_events e,vehicles v where w.job_id=j.id and e.id=w.event_id and v.id=j.vehicle_id and w.status='leased' and w.lease_until<now() and (j.route_version<>w.route_version or v.gps_event_id<>e.id or e.recorded_at<now()-interval '2 minutes');
 update tracking_work w set status='failed',finished_at=now(),last_error='Lease exhausted' where w.status='leased' and w.lease_until<now() and w.attempts>=5;
 return query with ranked as(
  select w.id,row_number() over(partition by w.tenant_id order by w.created_at,w.id) as tenant_turn
  from tracking_work w join jobs j on j.id=w.job_id
  where (w.status='pending' and w.available_at<=now() or w.status='leased' and w.lease_until<now())
   and w.attempts<5 and j.eta_next_calculation_at<=now()
   and not exists(select 1 from tracking_work l where l.job_id=w.job_id and l.status='leased' and l.lease_until>=now())
 ), candidates as(
  select w.id from tracking_work w join ranked r on r.id=w.id order by r.tenant_turn,w.created_at,w.id
  for update of w skip locked limit least(greatest(batch_size,1),10)
 ), claimed as(
  update tracking_work w set status='leased',lease_until=now()+interval '60 seconds',lease_token=gen_random_uuid(),attempts=w.attempts+1
  from candidates c where w.id=c.id returning w.*
 ) select c.id,c.lease_token,e.lat,e.lng,e.recorded_at,c.to_lat,c.to_lng from claimed c join tracking_events e on e.id=c.event_id and e.tenant_id=c.tenant_id;
end $$;
create or replace function finish_eta_work(work_id uuid,token uuid,new_eta timestamptz,route_provider text) returns boolean language plpgsql security definer set search_path=public as $$
declare w tracking_work;j jobs;e tracking_events;latest eta_history;published eta_history;estimate uuid;
begin
 select * into w from tracking_work where id=work_id;
 if not found then raise exception using errcode='40001',message='ETA work missing';end if;
 select * into j from jobs where id=w.job_id and tenant_id=w.tenant_id for update;
 select * into w from tracking_work where id=work_id for update;
 if w.status<>'leased' or w.lease_token is distinct from token or w.lease_until<now() then raise exception using errcode='40001',message='ETA lease expired';end if;
 select * into e from tracking_events where id=w.event_id and tenant_id=w.tenant_id;
 select * into latest from eta_history where id=j.current_eta_id and tenant_id=j.tenant_id;
 if j.route_version<>w.route_version or job_stop(j.status) is distinct from w.stop_type or e.recorded_at<now()-interval '2 minutes'
 or (latest.route_version=w.route_version and latest.source_recorded_at>e.recorded_at) then
  update tracking_work set status='superseded',finished_at=now() where id=work_id;return false;
 end if;
 if new_eta is null or route_provider is null then raise exception using errcode='23514',message='Routing result required';end if;
 insert into eta_history(tenant_id,job_id,eta,provider,source_event_id,source_recorded_at,route_version,stop_type,valid_until)
 values(w.tenant_id,j.id,new_eta,route_provider,e.id,e.recorded_at,w.route_version,w.stop_type,least(now()+interval '15 minutes',e.recorded_at+interval '30 minutes')) returning id into estimate;
 select * into published from eta_history where id=j.published_eta_id and tenant_id=j.tenant_id;
 update jobs set eta=new_eta,current_eta_id=estimate,eta_state='fresh',eta_approved=false,eta_next_calculation_at=now()+interval '60 seconds',
 published_eta_id=case when published.route_version=w.route_version and published.stop_type=w.stop_type and published.valid_until>now() and abs(extract(epoch from(new_eta-published.eta)))<=900 then published.id else null end where id=j.id;
 update tracking_work set status='done',finished_at=now(),last_error=null where id=work_id;
 update tracking_work set available_at=greatest(available_at,now()+interval '60 seconds') where job_id=j.id and status='pending';return true;
end $$;
create or replace function fail_eta_work(work_id uuid,token uuid,error_code text) returns void language plpgsql security definer set search_path=public as $$
declare w tracking_work;pending_id uuid;retry_at timestamptz;
begin
 select * into w from tracking_work where id=work_id;
 if not found then raise exception using errcode='40001',message='ETA work missing';end if;
 perform 1 from jobs where id=w.job_id for update;
 select * into w from tracking_work where id=work_id for update;
 if w.status<>'leased' or w.lease_token is distinct from token or w.lease_until<now() then raise exception using errcode='40001',message='ETA lease changed';end if;
 retry_at:=now()+make_interval(secs=>least(300,30*(2^w.attempts)::int));
 select id into pending_id from tracking_work where job_id=w.job_id and status='pending';
 if pending_id is not null then
  update tracking_work set status='superseded',finished_at=now(),last_error=left(error_code,100) where id=work_id;
  update tracking_work set available_at=greatest(available_at,retry_at),last_error=left(error_code,100) where id=pending_id;
 else
  update tracking_work set status=case when attempts>=5 then 'failed' else 'pending' end,available_at=retry_at,lease_until=null,last_error=left(error_code,100),finished_at=case when attempts>=5 then now() else null end where id=work_id;
 end if;
 update jobs set eta_state='unavailable',eta_next_calculation_at=retry_at where id=w.job_id and route_version=w.route_version;
end $$;
create or replace function approve_eta(t uuid,j uuid,expected_eta_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare job jobs;e eta_history;latest eta_history;v vehicles;
begin
 if not has_tenant(t,true,true) then raise exception using errcode='42501',message='Forbidden';end if;
 select * into job from jobs where tenant_id=t and id=j for update;
 if not found then raise exception using errcode='P0002',message='Job not found';end if;
 select * into e from eta_history where tenant_id=t and job_id=j and id=expected_eta_id;
 select * into latest from eta_history where tenant_id=t and id=job.current_eta_id;
 select * into v from vehicles where tenant_id=t and id=job.vehicle_id;
 if e.id is null or e.valid_until<=now() or e.source_recorded_at<now()-interval '15 minutes' or e.route_version<>job.route_version
 or e.stop_type is distinct from job_stop(job.status) or v.gps_at is null or v.gps_at<now()-interval '30 minutes'
 or (latest.route_version=e.route_version and abs(extract(epoch from(latest.eta-e.eta)))>900) then
  raise exception using errcode='40001',message='Estimate is stale or materially changed; review the latest';
 end if;
 update eta_history set approved_by=auth.uid(),approved_at=now(),valid_until=least(now()+interval '15 minutes',source_recorded_at+interval '30 minutes') where id=e.id;
 update jobs set published_eta_id=e.id,eta_approved=(current_eta_id=e.id) where id=j;
end $$;
-- Add explicit provenance to both staff calculations and customer publication.
drop function approved_etas();
create function approved_etas() returns table(job_id uuid,eta timestamptz,eta_id uuid,eta_state text,eta_source_at timestamptz,eta_valid_until timestamptz,eta_stop text,eta_mode text,eta_reviewed_at timestamptz) language sql stable security definer set search_path=public as $$
 with estimates as(
  select j.id,j.tenant_id,case when v.gps_at is null or v.gps_at<now()-interval '2 minutes' then 'awaiting recent GPS' else j.eta_state end as processing,has_tenant(j.tenant_id,false,true) as staff,
   case when c.route_version=j.route_version and c.stop_type=job_stop(j.status) and c.valid_until>now() then c.id end as calculated,
   case when p.route_version=j.route_version and p.stop_type=job_stop(j.status) and p.valid_until>now() and p.approved_at is not null and v.gps_at>=now()-interval '30 minutes' then p.id end as published
  from jobs j join vehicles v on v.id=j.vehicle_id and v.tenant_id=j.tenant_id
  left join eta_history c on c.id=j.current_eta_id and c.tenant_id=j.tenant_id
  left join eta_history p on p.id=j.published_eta_id and p.tenant_id=j.tenant_id where has_tenant(j.tenant_id)
 ), selected as(select s.*,case when staff and calculated is not null then calculated else published end as displayed from estimates s)
 select s.id,e.eta,case when s.staff then s.calculated end,
 case when s.displayed=s.published then case when s.processing='unavailable' then 'reviewed; routing unavailable' when s.processing='awaiting recent GPS' then 'reviewed; awaiting GPS for recalculation' else 'last reviewed' end
 when s.displayed is not null then case when s.processing='pending' then 'calculated; refreshing' else 'calculated; review required' end
 when s.processing='fresh' then 'awaiting review' else s.processing end,
 e.source_recorded_at,e.valid_until,e.stop_type,
 case when s.displayed=s.published then 'reviewed' when s.displayed is not null then 'calculated' else 'unavailable' end,e.approved_at
 from selected s left join eta_history e on e.id=s.displayed and e.tenant_id=s.tenant_id;
$$;
-- Guarded health/retry functions expose only the selected controller's tenant.
create function eta_queue_health(t uuid) returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not has_tenant(t,false,true) then raise exception using errcode='42501',message='Forbidden';end if;
 return jsonb_build_object('pending',(select count(*) from tracking_work where tenant_id=t and status='pending'),
 'ready',(select count(*) from tracking_work where tenant_id=t and status='pending' and available_at<=now()),
 'leased',(select count(*) from tracking_work where tenant_id=t and status='leased'),
 'failed',(select count(*) from tracking_work where tenant_id=t and status='failed'),
 'oldest_ready_seconds',(select coalesce(extract(epoch from(now()-min(available_at))),0) from tracking_work where tenant_id=t and status='pending' and available_at<=now()),
 'failures',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select job_id,last_error,attempts,finished_at from tracking_work where tenant_id=t and status='failed' order by finished_at desc limit 20)x));
end $$;
create function retry_job_eta(t uuid,j uuid) returns void language plpgsql security definer set search_path=public as $$
declare job jobs;v vehicles;
begin
 if not has_tenant(t,true,true) then raise exception using errcode='42501',message='Forbidden';end if;
 select * into job from jobs where tenant_id=t and id=j;
 if not found then raise exception using errcode='P0002',message='Job not found';end if;
 select * into v from vehicles where tenant_id=t and id=job.vehicle_id for update;
 select * into job from jobs where id=j for update;
 if job_stop(job.status) is null or v.gps_at is null or v.gps_at<now()-interval '2 minutes' then raise exception using errcode='23514',message='Active job and recent confirmed GPS required';end if;
 if exists(select 1 from tracking_work where job_id=j and status='leased' and lease_until>=now()) then raise exception using errcode='40001',message='A worker is already processing this job';end if;
 update tracking_work set status='superseded',finished_at=now() where job_id=j and status in('failed','leased');
 update jobs set eta_next_calculation_at=now() where id=j;
 update tracking_work set available_at=now(),attempts=0 where job_id=j and status='pending';
 perform enqueue_job_eta(j);
 insert into audit(tenant_id,entity_id,action,actor) values(t,j,'ETA retry requested',auth.uid()::text);
end $$;
revoke all on function approved_etas(),eta_queue_health(uuid),retry_job_eta(uuid,uuid) from public,anon,authenticated;
grant execute on function approved_etas(),eta_queue_health(uuid),retry_job_eta(uuid,uuid) to authenticated;
-- Re-establish latest work after the rollout invalidated old leases.
do $$ declare j record;begin for j in select id from jobs where job_stop(status) is not null loop perform enqueue_job_eta(j.id);end loop;end $$;
create or replace function queue_after_dispatch() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.route_version<>old.route_version then
  update jobs set eta_next_calculation_at=now(),published_eta_id=null,current_eta_id=null,eta=null,eta_approved=false where id=new.id;
  perform enqueue_job_eta(new.id);
 end if;
 return new;
end $$;
create function worker_queue_health() returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('pending',count(*) filter(where status='pending'),'ready',count(*) filter(where status='pending' and available_at<=now()),'leased',count(*) filter(where status='leased'),'failed',count(*) filter(where status='failed'),
 'oldest_ready_seconds',coalesce(extract(epoch from(now()-min(available_at) filter(where status='pending' and available_at<=now()))),0)) from tracking_work;
$$;
revoke all on function worker_queue_health() from public,anon,authenticated;grant execute on function worker_queue_health() to service_role;
