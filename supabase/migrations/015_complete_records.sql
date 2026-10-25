-- Paging is a separate live view, not an overwrite of the coherent control-tower snapshot.
create function workspace_records(collection text,t uuid default null,page integer default 0,page_size integer default 50,query text default '') returns jsonb language plpgsql stable security invoker set search_path=public as $$
declare source text;ordering text;result jsonb;take integer:=least(greatest(page_size,1),100);
begin
 if page is null or page<0 or page>1000000 or page_size is null then raise exception using errcode='23514',message='Invalid page';end if;
 if t is not null and not has_tenant(t) then raise exception using errcode='42501',message='Forbidden';end if;
 source:=case collection
 when 'vehicles' then 'select to_jsonb(v) as payload,v.id,v.tenant_id from vehicles v'
 when 'drivers' then 'select to_jsonb(d) as payload,d.id,d.tenant_id from drivers d'
 when 'jobs' then 'select to_jsonb(j)||coalesce(to_jsonb(e)-''job_id'',''{}''::jsonb)||jsonb_build_object(''eta'',coalesce(to_jsonb(e.eta),''""''::jsonb)) as payload,j.id,j.tenant_id from visible_jobs j left join approved_etas() e on e.job_id=j.id'
 when 'documents' then 'select to_jsonb(d) as payload,d.id,d.tenant_id from documents d'
 when 'updates' then 'select to_jsonb(u) as payload,u.id,u.tenant_id from updates u'
 when 'alerts' then 'select to_jsonb(a) as payload,a.id,a.tenant_id from alerts a'
 when 'handover' then 'select to_jsonb(a) as payload,a.id,a.tenant_id from audit a where a.action like ''Shift handover:%'''
 when 'audit' then 'select to_jsonb(a) as payload,a.id,a.tenant_id from audit a'
 else null end;
 if source is null then raise exception using errcode='23514',message='Unknown collection';end if;
 ordering:=case when collection in('audit','handover','updates','documents','alerts') then 'payload->>''created_at'' desc,id desc' else 'id' end;
 execute 'with scoped as materialized(select * from ('||source||')s where ($1 is null or tenant_id=$1) and ($2='''' or payload::text ilike ''%''||$2||''%'')), items as(select payload from scoped order by '||ordering||' limit $3 offset $4) select jsonb_build_object(''records'',coalesce((select jsonb_agg(payload) from items),''[]''::jsonb),''total'',(select count(*) from scoped),''page'',$5,''page_size'',$3,''has_more'',(select count(*) from scoped)>$4+$3,''as_of'',now())'
 into result using t,left(coalesce(query,''),100),take,page*take,page;
 return result;
end $$;
revoke all on function workspace_records(text,uuid,integer,integer,text) from public,anon,authenticated;grant execute on function workspace_records(text,uuid,integer,integer,text) to authenticated;
-- Generate the complete scoped CSV in one statement snapshot; no PostgREST row cap.
create function csv_cell(value text) returns text language sql immutable set search_path=public as $$
 select '"'||replace(case when coalesce(value,'') ~ '^[[:space:][:cntrl:]]*[=+@-]' then ''''||coalesce(value,'') else coalesce(value,'') end,'"','""')||'"';
$$;
revoke all on function csv_cell(text) from public,anon;grant execute on function csv_cell(text) to authenticated,service_role;
create function export_jobs(t uuid default null) returns text language plpgsql stable security invoker set search_path=public as $$
declare result text;
begin
 if t is not null and not has_tenant(t) then raise exception using errcode='42501',message='Forbidden';end if;
 select '"Reference","Transporter","Fleet number","Loading customer","Delivery customer","Cargo","Route","Status","ETA stop","ETA mode","ETA source (UTC)","ETA (UTC)","Final delivery timing","Controller"'||E'\r\n'||coalesce(string_agg(
 csv_cell(j.reference)||','||csv_cell(c.name)||','||csv_cell(v.fleet_no)||','||csv_cell(j.loading_customer)||','||csv_cell(j.delivery_customer)||','||csv_cell(j.cargo)||','||csv_cell(j.loading_code||' → '||j.delivery_code)||','||csv_cell(j.status)||','||csv_cell(e.eta_stop)||','||csv_cell(e.eta_mode)||','||csv_cell(to_char(e.eta_source_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'))||','||csv_cell(to_char(e.eta at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'))||','||csv_cell(case when e.eta is null or e.eta_stop<>'delivery' then 'unknown' when e.eta>j.scheduled_at then 'delayed' else 'within window' end)||','||csv_cell(j.controller),E'\r\n' order by j.id),'') into result
 from visible_jobs j join tenants c on c.id=j.tenant_id join vehicles v on v.id=j.vehicle_id and v.tenant_id=j.tenant_id left join approved_etas() e on e.job_id=j.id where t is null or j.tenant_id=t;
 return result;
end $$;
revoke all on function export_jobs(uuid) from public,anon,authenticated;grant execute on function export_jobs(uuid) to authenticated;
-- Handovers stay visible when telemetry volume fills the raw audit collection.
create or replace function workspace_snapshot() returns jsonb language sql stable security invoker set search_path=public as $$
 with
 ts as materialized(select * from tenants order by id limit 1001),
 vs as materialized(select * from vehicles order by fleet_no,id limit 1001),
 ds as materialized(select * from drivers order by name,id limit 1001),
 js as materialized(select j.id,case when j.status in('Assigned','Accepted','En Route to Loading','At Loading','Loaded','In Transit','At Delivery','Exception') then 0 when j.status='Created' then 1 else 2 end as priority,
  to_jsonb(j)||coalesce(to_jsonb(e)-'job_id','{}'::jsonb)||jsonb_build_object('eta',coalesce(to_jsonb(e.eta),'""'::jsonb)) as payload from visible_jobs j left join approved_etas() e on e.job_id=j.id order by priority,j.id limit 1001),
 docs as materialized(select * from documents order by created_at desc,id desc limit 1001),
 als as materialized(select * from alerts order by case when status='resolved' then 1 else 0 end,created_at desc,id desc limit 1001),
 aus as materialized(select * from audit order by created_at desc,id desc limit 1001),
 handovers as materialized(select * from audit where action like 'Shift handover:%' order by created_at desc,id desc limit 1001),
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
 'handovers',(select coalesce(jsonb_agg(x order by x.created_at desc,x.id desc),'[]'::jsonb) from(select * from handovers limit 1000)x),
 'updates',(select coalesce(jsonb_agg(x order by x.created_at desc,x.id desc),'[]'::jsonb) from(select * from ups limit 1000)x),
 'capabilities',(select coalesce(jsonb_object_agg(tenant_id,role),'{}'::jsonb) from ms),
 'role',case when exists(select 1 from ms where role='admin') then 'admin' when exists(select 1 from ms where role='controller') then 'controller' when exists(select 1 from ms where role='customer_admin') then 'customer_admin' else 'customer_viewer' end,
 'truncated',(select coalesce(jsonb_agg(name),'[]'::jsonb) from(values('tenants',(select count(*) from ts)),('vehicles',(select count(*) from vs)),('drivers',(select count(*) from ds)),('jobs',(select count(*) from js)),('documents',(select count(*) from docs)),('alerts',(select count(*) from als)),('audit',(select count(*) from aus)),('handovers',(select count(*) from handovers)),('updates',(select count(*) from ups))) as sizes(name,n) where n>1000)
 );
$$;

-- Staff source IDs describe the displayed estimate, including a valid reviewed fallback.
create or replace function approved_etas() returns table(job_id uuid,eta timestamptz,eta_id uuid,eta_state text,eta_source_at timestamptz,eta_valid_until timestamptz,eta_stop text,eta_mode text,eta_reviewed_at timestamptz) language sql stable security definer set search_path=public as $$
 with estimates as(
  select j.id,j.tenant_id,case when v.gps_at is null or v.gps_at<now()-interval '2 minutes' then 'awaiting recent GPS' else j.eta_state end as processing,has_tenant(j.tenant_id,false,true) as staff,
   case when c.route_version=j.route_version and c.stop_type=job_stop(j.status) and c.valid_until>now() then c.id end as calculated,
   case when p.route_version=j.route_version and p.stop_type=job_stop(j.status) and p.valid_until>now() and p.approved_at is not null and v.gps_at>=now()-interval '30 minutes' then p.id end as published
  from jobs j join vehicles v on v.id=j.vehicle_id and v.tenant_id=j.tenant_id
  left join eta_history c on c.id=j.current_eta_id and c.tenant_id=j.tenant_id
  left join eta_history p on p.id=j.published_eta_id and p.tenant_id=j.tenant_id where has_tenant(j.tenant_id)
 ), selected as(select s.*,case when staff and calculated is not null then calculated else published end as displayed from estimates s)
 select s.id,e.eta,case when s.staff then s.displayed end,
 case when s.displayed=s.published then case when s.processing='unavailable' then 'reviewed; routing unavailable' when s.processing='awaiting recent GPS' then 'reviewed; awaiting GPS for recalculation' else 'last reviewed' end
 when s.displayed is not null then case when s.processing='pending' then 'calculated; refreshing' else 'calculated; review required' end
 when s.processing='fresh' then 'awaiting review' else s.processing end,
 e.source_recorded_at,e.valid_until,e.stop_type,
 case when s.displayed=s.published then 'reviewed' when s.displayed is not null then 'calculated' else 'unavailable' end,e.approved_at
 from selected s left join eta_history e on e.id=s.displayed and e.tenant_id=s.tenant_id;
$$;
