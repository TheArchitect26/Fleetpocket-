create function public.create_fleet_vehicle(payload jsonb) returns uuid language plpgsql security invoker set search_path=public as $$ declare driver uuid;vehicle uuid;t uuid:=(payload->>'tenant_id')::uuid;begin
if not public.has_tenant(t,true,true) then raise exception 'Forbidden';end if;
insert into drivers(tenant_id,name,phone,licence_expiry,prdp_expiry) values(t,payload->>'name',payload->>'phone',(payload->>'licence_expiry')::date,(payload->>'prdp_expiry')::date) returning id into driver;
insert into vehicles(tenant_id,fleet_no,horse_reg,trailer_one,trailer_two,driver_id) values(t,payload->>'fleet_no',payload->>'horse_reg',payload->>'trailer_one',payload->>'trailer_two',driver) returning id into vehicle;return vehicle;end $$;
revoke all on function create_fleet_vehicle(jsonb) from public;grant execute on function create_fleet_vehicle(jsonb) to authenticated;
