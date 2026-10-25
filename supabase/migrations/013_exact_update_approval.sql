-- Approved communication is an immutable, transactional snapshot.
alter table updates add column job_id uuid;
alter table updates add column approved_by uuid;
alter table updates add column approved_at timestamptz;
alter table updates add column valid_until timestamptz;
alter table updates add column request_key uuid;
alter table updates add column source_snapshot jsonb not null default '{}';
alter table updates add foreign key(tenant_id,job_id) references jobs(tenant_id,id);
alter table updates add constraint update_request_key unique(tenant_id,request_key);
revoke insert,update,delete on updates from authenticated;
create function approve_vehicle_update(t uuid,v uuid,j uuid,body text,minutes integer,key uuid,expected_job_version integer default null,expected_eta_id uuid default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare vehicle vehicles;job jobs;existing updates;saved updates;history eta_history;
begin
 if not has_tenant(t,true,true) then raise exception using errcode='42501',message='Forbidden';end if;
 if key is null or length(body) not between 30 and 6000 or minutes not between 5 and 1440 or body is null or minutes is null then raise exception using errcode='23514',message='Complete update, interval and request key required';end if;
 select * into vehicle from vehicles where tenant_id=t and id=v for update;
 if not found then raise exception using errcode='P0002',message='Vehicle unavailable';end if;
 select * into existing from updates where tenant_id=t and request_key=key;
 if found then
  if (existing.vehicle_id,existing.job_id,existing.text,existing.interval_minutes,(existing.source_snapshot->>'job_version')::int,(existing.source_snapshot->>'eta_id')::uuid) is distinct from (v,j,body,minutes,expected_job_version,expected_eta_id) then raise exception using errcode='40001',message='Request key belongs to a different update';end if;
  return jsonb_build_object('id',existing.id,'vehicle_id',v,'job_id',j,'text',existing.text,'interval_minutes',existing.interval_minutes,'valid_until',existing.valid_until,'job_version',existing.source_snapshot->'job_version');
 end if;
 select * into job from jobs where tenant_id=t and vehicle_id=v and id=j for update;
 if not found then raise exception using errcode='23514',message='Update job must match its vehicle';end if;
 if expected_job_version is null or expected_job_version<>job.version then raise exception using errcode='40001',message='Job changed; review the update against the current job';end if;
 if expected_eta_id is not null then
  select * into history from eta_history where tenant_id=t and job_id=j and id=expected_eta_id and route_version=job.route_version and stop_type=job_stop(job.status) and valid_until>now();
  if not found then raise exception using errcode='40001',message='Preview ETA expired or changed; regenerate before approving';end if;
 end if;
 insert into updates(tenant_id,vehicle_id,job_id,text,interval_minutes,approved,approved_by,approved_at,valid_until,request_key,source_snapshot)
 values(t,v,j,body,minutes,true,auth.uid(),now(),least(now()+interval '15 minutes',coalesce(history.valid_until,now()+interval '15 minutes')),key,
 jsonb_build_object('gps_event_id_at_approval',vehicle.gps_event_id,'gps_at_approval',vehicle.gps_at,'location_at_approval',vehicle.location,'load_status_at_approval',vehicle.load_status,'job_version',job.version,'route_version',job.route_version,'eta_id',history.id)) returning * into saved;
 return jsonb_build_object('id',saved.id,'vehicle_id',v,'job_id',j,'text',saved.text,'interval_minutes',saved.interval_minutes,'valid_until',saved.valid_until,'job_version',saved.source_snapshot->'job_version');
end $$;
revoke all on function approve_vehicle_update(uuid,uuid,uuid,text,integer,uuid,integer,uuid) from public,anon,authenticated;
grant execute on function approve_vehicle_update(uuid,uuid,uuid,text,integer,uuid,integer,uuid) to authenticated;
