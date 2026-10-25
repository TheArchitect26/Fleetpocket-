-- An incident has one stable condition identity. Acknowledgement is not resolution.
drop index alerts_open_dedupe;
alter table alerts alter column vehicle_id drop not null;
alter table alerts add column condition_key text;
alter table alerts add column condition_active boolean not null default false;
alter table alerts add column status text not null default 'open' check(status in('open','acknowledged','resolved'));
alter table alerts add column version integer not null default 1;
alter table alerts add column occurrence integer not null default 1;
alter table alerts add column assigned_to uuid;
alter table alerts add column resolved_by uuid;
alter table alerts add column resolved_at timestamptz;
alter table alerts add column resolution text;
alter table alerts add column last_observed_at timestamptz;
update alerts set status=case when acknowledged then 'acknowledged' else 'open' end;
create unique index incident_condition on alerts(tenant_id,condition_key) where condition_key is not null;
revoke insert,update,delete on alerts from authenticated;
create view fleet_conditions with(security_invoker=true) as
 select v.tenant_id,v.id as vehicle_id,'gps:'||v.id as condition_key,'warning'::text as severity,'Stale GPS signal'::text as title,'No confirmed GPS received for over 30 minutes'::text as detail
 from vehicles v where v.gps_at is null or v.gps_at<now()-interval '30 minutes'
 union all
 select j.tenant_id,j.vehicle_id,'delay:'||j.id,'critical','Delivery at risk',j.reference||': valid delivery ETA exceeds the window by over 30 minutes'
 from jobs j join eta_history e on e.id=j.current_eta_id and e.tenant_id=j.tenant_id
 where j.status in('Loaded','In Transit','At Delivery') and e.route_version=j.route_version and e.stop_type='delivery' and e.valid_until>now() and e.eta>j.scheduled_at+interval '30 minutes'
 union all
 select v.tenant_id,v.id,'stop:'||v.id,'warning','Unexpected stop','Zero-speed GPS samples for 20 minutes in transit. Controller confirmation required.'
 from vehicles v where v.gps_at>now()-interval '10 minutes' and exists(select 1 from jobs j where j.vehicle_id=v.id and j.tenant_id=v.tenant_id and j.status='In Transit')
 and (select count(*) from tracking_events e where e.vehicle_id=v.id and e.tenant_id=v.tenant_id and e.recorded_at>now()-interval '25 minutes')>=3
 and not exists(select 1 from tracking_events e where e.vehicle_id=v.id and e.tenant_id=v.tenant_id and e.recorded_at>now()-interval '25 minutes' and e.speed>3)
 and exists(select 1 from tracking_events e where e.vehicle_id=v.id and e.tenant_id=v.tenant_id and e.recorded_at between now()-interval '25 minutes' and now()-interval '20 minutes')
 union all
 select d.tenant_id,d.vehicle_id,'document:'||d.id,'warning','Document expiring',d.name||' expires '||d.expires_at::date from documents d where d.expires_at<now()+interval '30 days'
 union all
 select d.tenant_id,null::uuid,'licence:'||d.id,'warning','Driver licence expiring',d.name||': licence expires '||d.licence_expiry::text from drivers d where d.licence_expiry<=current_date+30
 union all
 select d.tenant_id,null::uuid,'prdp:'||d.id,'warning','PrDP expiring',d.name||': PrDP expires '||d.prdp_expiry::text from drivers d where d.prdp_expiry<=current_date+30
 union all
 select j.tenant_id,j.vehicle_id,'pod:'||j.id,'warning','Missing POD',j.reference||': delivered; matching verified POD outstanding' from jobs j where j.status='Delivered' and not exists(select 1 from documents d where d.tenant_id=j.tenant_id and d.job_id=j.id and d.vehicle_id=j.vehicle_id and d.kind='Proof of delivery' and d.verified)
 union all
 select v.tenant_id,v.id,'update:'||v.id,'warning','Vehicle update due',case when u.id is null then 'First approved vehicle update required' else 'Approved update due since '||(u.created_at+make_interval(mins=>u.interval_minutes))::text end
 from vehicles v left join lateral(select x.* from updates x where x.tenant_id=v.tenant_id and x.vehicle_id=v.id and x.approved order by x.created_at desc,x.id desc limit 1)u on true
 where exists(select 1 from jobs j where j.tenant_id=v.tenant_id and j.vehicle_id=v.id and j.status in('Assigned','Accepted','En Route to Loading','At Loading','Loaded','In Transit','At Delivery','Exception'))
 and (u.id is null or u.created_at+make_interval(mins=>u.interval_minutes)<=now());
revoke all on fleet_conditions from public,anon,authenticated;grant select on fleet_conditions to service_role;
create or replace function monitor_fleet() returns integer language plpgsql security definer set search_path=public as $$
declare affected integer;
begin
 perform pg_advisory_xact_lock(hashtext('fleet_monitor_v2'));
 update alerts a set condition_active=false,status='resolved',acknowledged=true,resolved_at=coalesce(a.resolved_at,now()),resolution=coalesce(a.resolution,'Condition no longer observed'),version=version+1
 where a.condition_key is not null and a.condition_active and not exists(select 1 from fleet_conditions c where c.tenant_id=a.tenant_id and c.condition_key=a.condition_key);
 insert into alerts(tenant_id,vehicle_id,condition_key,severity,title,detail,condition_active,last_observed_at)
 select tenant_id,vehicle_id,condition_key,severity,title,detail,true,now() from fleet_conditions
 on conflict(tenant_id,condition_key) where condition_key is not null do update set
 vehicle_id=excluded.vehicle_id,severity=excluded.severity,title=excluded.title,detail=excluded.detail,last_observed_at=now(),condition_active=true,
 status=case when not alerts.condition_active then 'open' else alerts.status end,
 acknowledged=case when not alerts.condition_active then false else alerts.acknowledged end,
 occurrence=alerts.occurrence+case when not alerts.condition_active then 1 else 0 end,
 version=alerts.version+case when not alerts.condition_active or alerts.detail is distinct from excluded.detail then 1 else 0 end,
 resolved_at=case when not alerts.condition_active then null else alerts.resolved_at end,
 resolved_by=case when not alerts.condition_active then null else alerts.resolved_by end,
 resolution=case when not alerts.condition_active then null else alerts.resolution end;
 get diagnostics affected=row_count;return affected;
end $$;
create function incident_command(t uuid,a uuid,expected_version integer,command text,note text default null) returns integer language plpgsql security definer set search_path=public as $$
declare incident alerts;result integer;
begin
 if not has_tenant(t,true,true) then raise exception using errcode='42501',message='Forbidden';end if;
 select * into incident from alerts where tenant_id=t and id=a for update;
 if not found then raise exception using errcode='P0002',message='Incident unavailable';end if;
 if expected_version is null or incident.version<>expected_version then raise exception using errcode='40001',message='Incident changed; refresh';end if;
 if command='acknowledge' then
  if incident.status='resolved' then raise exception using errcode='23514',message='Incident already resolved';end if;
  if incident.status='acknowledged' then return incident.version;end if;
  update alerts set acknowledged=true,status='acknowledged',version=version+1 where id=a returning version into result;
 elsif command='claim' then
  update alerts set assigned_to=auth.uid(),version=version+1 where id=a returning version into result;
 elsif command='resolve' then
  if length(trim(coalesce(note,''))) not between 3 and 1000 then raise exception using errcode='23514',message='Resolution note required';end if;
  if incident.status='resolved' then return incident.version;end if;
  update alerts set status='resolved',acknowledged=true,resolved_by=auth.uid(),resolved_at=now(),resolution=trim(note),version=version+1 where id=a returning version into result;
 else raise exception using errcode='23514',message='Unknown incident command';end if;
 return result;
end $$;
revoke all on function incident_command(uuid,uuid,integer,text,text) from public,anon,authenticated;grant execute on function incident_command(uuid,uuid,integer,text,text) to authenticated;
revoke all on function monitor_fleet() from public,anon,authenticated;grant execute on function monitor_fleet() to service_role;
