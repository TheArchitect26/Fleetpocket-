begin;
create extension if not exists pgtap with schema extensions;
select plan(5);
insert into tenants(id,name,code) values('15151515-1515-4515-8515-151515151515','Busy tenant','BUSY'),('16161616-1616-4616-8616-161616161616','Small tenant','SMALL');
do $$declare t uuid;v uuid;j uuid;i int;k int;begin
 for i in 1..7 loop
  t:=case when i=7 then '16161616-1616-4616-8616-161616161616'::uuid else '15151515-1515-4515-8515-151515151515'::uuid end;
  v:=gen_random_uuid();j:=gen_random_uuid();
  insert into vehicles(id,tenant_id,fleet_no,horse_reg,provider) values(v,t,'QUEUE-'||i,'CA QUEUE '||i,'Cartrack');
  insert into jobs(id,tenant_id,vehicle_id,loading_code,loading_customer,delivery_code,delivery_customer,cargo,status,scheduled_at,destination_lat,destination_lng) values(j,t,v,'CPT','Collection','DBN','Delivery','Goods','In Transit',now()+interval '1 day',-29,31);
  for k in 1..20 loop
   perform ingest_gps(jsonb_build_object('tenant_id',t,'vehicle_id',v,'provider','Cartrack','event_id','burst-'||k,'lat',-30,'lng',28,'speed',60,'recorded_at',now()-make_interval(secs=>21-k)));
  end loop;
 end loop;
end $$;
select is((select count(*)::int from tracking_events),140,'every confirmed burst sample retained');
select is((select count(*)::int from tracking_work where status='pending'),7,'one pending calculation per job');
select ok(not exists(select 1 from tracking_work w join jobs j on j.id=w.job_id join vehicles v on v.id=j.vehicle_id where w.status='pending' and w.event_id<>v.gps_event_id),'pending sources follow newest confirmed events');
create temporary table leased as select * from claim_eta_work(5);
select is((select count(*)::int from tracking_work where id in(select id from leased) and tenant_id='16161616-1616-4616-8616-161616161616'),1,'small tenant gets a turn within a busy fleet batch');
select is((select count(*)::int from claim_eta_work(5)),2,'next batch drains remaining jobs without duplicate leases');
select * from finish();rollback;
