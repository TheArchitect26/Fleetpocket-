-- Prevent indirect disclosure of unpublished ETAs and message drafts.
drop policy tenant_read on eta_history;
create policy controller_read on eta_history for select to authenticated using(public.has_tenant(tenant_id,false,true));
drop policy tenant_read on updates;
create policy approved_update_read on updates for select to authenticated using(public.has_tenant(tenant_id) and (approved or public.has_tenant(tenant_id,false,true)));
alter table vehicles add column group_name text not null default 'General fleet' check(length(group_name) between 1 and 80);

create or replace function public.create_fleet_vehicle(payload jsonb) returns uuid language plpgsql security invoker set search_path=public as $$ declare driver uuid;vehicle uuid;t uuid:=(payload->>'tenant_id')::uuid;begin
if not public.has_tenant(t,true,true) then raise exception 'Forbidden';end if;
insert into drivers(tenant_id,name,phone,licence_expiry,prdp_expiry) values(t,payload->>'name',payload->>'phone',(payload->>'licence_expiry')::date,(payload->>'prdp_expiry')::date) returning id into driver;
insert into vehicles(tenant_id,fleet_no,horse_reg,trailer_one,trailer_two,driver_id,group_name) values(t,payload->>'fleet_no',payload->>'horse_reg',payload->>'trailer_one',payload->>'trailer_two',driver,coalesce(payload->>'group_name','General fleet')) returning id into vehicle;return vehicle;end $$;
