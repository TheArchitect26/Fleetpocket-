begin;
create extension if not exists pgtap with schema extensions;
select plan(6);
insert into auth.users(id,email) values('90909090-9090-4090-8090-909090909090','multi-job@fleet.test');
insert into tenants(id,name,code) values('10101010-1010-4010-8010-101010101010','Multi-job','MULTI');
insert into memberships values('10101010-1010-4010-8010-101010101010','90909090-9090-4090-8090-909090909090','controller');
insert into vehicles(id,tenant_id,fleet_no,horse_reg,load_status) values('20202020-2020-4020-8020-202020202020','10101010-1010-4010-8010-101010101010','MULTI-1','CA MULTI','Loaded');
insert into jobs(id,tenant_id,vehicle_id,loading_code,loading_customer,delivery_code,delivery_customer,cargo,status,scheduled_at,destination_lat,destination_lng) values
 ('41414141-4141-4141-8141-414141414141','10101010-1010-4010-8010-101010101010','20202020-2020-4020-8020-202020202020','CPT','Old','DBN','Old delivery','Old cargo','Delivered',now(),-29,31),
 ('42424242-4242-4242-8242-424242424242','10101010-1010-4010-8010-101010101010','20202020-2020-4020-8020-202020202020','CPT','New','DBN','New delivery','New cargo','Loaded',now(),-29,31);
insert into documents(tenant_id,name,kind,vehicle_id,job_id,path,verified) values('10101010-1010-4010-8010-101010101010','Old verified POD','Proof of delivery','20202020-2020-4020-8020-202020202020','41414141-4141-4141-8141-414141414141','10101010-1010-4010-8010-101010101010/old.pdf',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','90909090-9090-4090-8090-909090909090',true);
select is(dispatch_job('10101010-1010-4010-8010-101010101010','41414141-4141-4141-8141-414141414141',1,'POD Received'),2,'old POD received');
select is((select load_status from vehicles limit 1),'Loaded','old POD does not unload newer job');
select is(dispatch_job('10101010-1010-4010-8010-101010101010','41414141-4141-4141-8141-414141414141',2,'Closed'),3,'old job closed');
select is((select load_status from vehicles limit 1),'Loaded','old closure does not unload newer job');
select is(dispatch_job('10101010-1010-4010-8010-101010101010','41414141-4141-4141-8141-414141414141',3,'Closed'),3,'same-state closed command is idempotent');
select is((select load_status from vehicles limit 1),'Loaded','repeated paperwork cannot unload newer job');
select * from finish();rollback;
