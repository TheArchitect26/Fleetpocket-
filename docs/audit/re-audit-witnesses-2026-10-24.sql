-- SOURCE-REVIEW REPRODUCTION WITNESSES. Not executed during this audit.
-- Run only as the database owner in a disposable local Supabase project with
-- migrations 001-009 applied. Never run against production. ROLLBACK removes fixtures.
begin;
insert into auth.users(id,email) values('90909090-9090-4090-8090-909090909090','reaudit-controller@fleet.test');
insert into tenants(id,name,code) values('10101010-1010-4010-8010-101010101010','Reaudit disposable','REAUDIT');
insert into memberships values('10101010-1010-4010-8010-101010101010','90909090-9090-4090-8090-909090909090','controller');
insert into vehicles(id,tenant_id,fleet_no,horse_reg,provider,load_status) values
 ('20202020-2020-4020-8020-202020202020','10101010-1010-4010-8010-101010101010','AUDIT-1','CA AUDIT 1','Cartrack','Loaded'),
 ('30303030-3030-4030-8030-303030303030','10101010-1010-4010-8010-101010101010','AUDIT-2','CA AUDIT 2','Cartrack','Loaded');
insert into jobs(id,tenant_id,vehicle_id,loading_code,loading_customer,delivery_code,delivery_customer,cargo,status,scheduled_at,destination_lat,destination_lng,loading_lat,loading_lng) values
 ('41414141-4141-4141-8141-414141414141','10101010-1010-4010-8010-101010101010','20202020-2020-4020-8020-202020202020','CPT','Old collection','DBN','Old delivery','Prior load','Delivered',now()+interval '1 day',-29,31,-33,18),
 ('42424242-4242-4242-8242-424242424242','10101010-1010-4010-8010-101010101010','20202020-2020-4020-8020-202020202020','CPT','New collection','DBN','New delivery','Current load','Loaded',now()+interval '1 day',-29,31,-33,18),
 ('43434343-4343-4343-8343-434343434343','10101010-1010-4010-8010-101010101010','30303030-3030-4030-8030-303030303030','CPT','ETA collection','DBN','ETA delivery','ETA load','In Transit',now()+interval '1 day',-29,31,-33,18);
-- Trusted fixture represents already-verified evidence for the old delivered job.
-- This does not test upload or verification permissions; the existing suite covers those separately.
insert into documents(id,tenant_id,name,kind,vehicle_id,job_id,path,verified) values
 ('51515151-5151-4151-8151-515151515151','10101010-1010-4010-8010-101010101010','Existing verified old POD','Proof of delivery','20202020-2020-4020-8020-202020202020','41414141-4141-4141-8141-414141414141','10101010-1010-4010-8010-101010101010/existing-old-pod.pdf',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','90909090-9090-4090-8090-909090909090',true);
-- R01: only the old job's paperwork changes. The newer live job still owns a load.
select dispatch_job('10101010-1010-4010-8010-101010101010','41414141-4141-4141-8141-414141414141',1,'POD Received');
select 'R01' as witness,j.status as newer_job_status,v.load_status as vehicle_load_status
from visible_jobs j join vehicles v on v.id=j.vehicle_id
where j.id='42424242-4242-4242-8242-424242424242';
-- Source-predicted result: Loaded / Empty. Required result: Loaded / Loaded.
reset role;
-- R02: construct one correctly completed ETA work item using the actual worker RPCs.
select ingest_gps(jsonb_build_object('tenant_id','10101010-1010-4010-8010-101010101010','vehicle_id','30303030-3030-4030-8030-303030303030','provider','Cartrack','event_id','reaudit-gps','lat',-30,'lng',28,'speed',70,'recorded_at',now()-interval '1 minute'));
create temporary table reaudit_claims as select * from claim_eta_work(10);
select finish_eta_work(c.id,c.lease_token,now()+interval '2 hours','audit-fixture') from reaudit_claims c
join tracking_work w on w.id=c.id where w.job_id='43434343-4343-4343-8343-434343434343';
select 'R02 before' as witness,j.version,j.eta_state,j.current_eta_id is not null as has_eta,w.status as work_status
from jobs j join tracking_work w on w.job_id=j.id where j.id='43434343-4343-4343-8343-434343434343';
set local role authenticated;
select dispatch_job('10101010-1010-4010-8010-101010101010','43434343-4343-4343-8343-434343434343',1,'In Transit');
reset role;
select 'R02 after same-state PATCH' as witness,j.version,j.eta_state,j.current_eta_id is not null as has_eta,w.status as work_status
from jobs j join tracking_work w on w.job_id=j.id where j.id='43434343-4343-4343-8343-434343434343';
-- Source-predicted result: version 1, pending, has_eta false, work done.
-- Required behavior: reject the no-op, or preserve the current ETA/work state.
rollback;
