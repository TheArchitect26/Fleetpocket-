begin;
create extension if not exists pgtap with schema extensions;
select plan(10);
insert into public.tenants(id,name,code) values('44444444-4444-4444-8444-444444444444','Tracking Test','TRACK');
insert into public.vehicles(id,tenant_id,fleet_no,horse_reg,provider) values('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','44444444-4444-4444-8444-444444444444','T-1','CA TEST','Cartrack');
create function pg_temp.gps(event text,age integer,latitude float8 default -29,provider_name text default 'Cartrack',tenant text default '44444444-4444-4444-8444-444444444444') returns jsonb language sql as $$
 select jsonb_build_object('tenant_id',tenant,'vehicle_id','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','provider',provider_name,'event_id',event,'lat',latitude,'lng',31,'speed',70,'recorded_at',now()-make_interval(mins=>age));
$$;
select is(public.ingest_gps(pg_temp.gps('1',1)),true,'first confirmed event ingested');
select is(public.ingest_gps(pg_temp.gps('1',1)),false,'duplicate event idempotent');
select is(public.ingest_gps(pg_temp.gps('0',5,-30)),false,'old event not promoted');
select is((select lat from vehicles where id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),-29::float8,'confirmed coordinates retained');
select is((select count(*)::int from tracking_events),2,'old readings retained');
select is(ingest_gps(pg_temp.gps('tie',1,-31)),false,'equal timestamp does not replace confirmed source');
select is((select lat from vehicles where id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),-29::float8,'equal timestamp coordinates cannot overwrite confirmation');
select is((select simulated from vehicles where id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),false,'real event not simulated');
select throws_ok($$select ingest_gps(pg_temp.gps('3',0,-29,'Netstar'))$$,'P0001','Provider mismatch','wrong provider rejected');
select throws_ok($$select ingest_gps(pg_temp.gps('4',0,-29,'Cartrack','55555555-5555-4555-8555-555555555555'))$$,'42501','Vehicle unavailable','wrong tenant rejected');
select * from finish();rollback;
