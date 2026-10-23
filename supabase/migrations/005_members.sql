create function public.list_tenant_members(t uuid) returns table(user_id uuid,email text,role text) language plpgsql security definer set search_path=public as $$ begin
if not exists(select 1 from memberships m where m.tenant_id=t and m.user_id=auth.uid() and m.role in('admin','customer_admin')) then raise exception 'Forbidden';end if;
return query select m.user_id,u.email::text,m.role from memberships m join auth.users u on u.id=m.user_id where m.tenant_id=t;end $$;
create function public.manage_tenant_member(t uuid,u uuid,new_role text) returns void language plpgsql security definer set search_path=public as $$ begin
if not exists(select 1 from memberships m where m.tenant_id=t and m.user_id=auth.uid() and m.role in('admin','customer_admin')) or u=auth.uid() then raise exception 'Forbidden';end if;
if new_role is not null and new_role not in('customer_admin','customer_viewer') then raise exception 'Customer role required';end if;
if exists(select 1 from memberships m where m.tenant_id=t and m.user_id=u and m.role in('admin','controller')) then raise exception 'Staff membership is managed outside the customer portal';end if;
if new_role is null then delete from memberships where tenant_id=t and user_id=u;else insert into memberships(tenant_id,user_id,role) values(t,u,new_role) on conflict(tenant_id,user_id) do update set role=excluded.role;end if;
insert into audit(tenant_id,entity_id,action,actor) values(t,u,'Customer membership '||coalesce(new_role,'removed'),auth.uid()::text);end $$;
revoke all on function list_tenant_members(uuid),manage_tenant_member(uuid,uuid,text) from public;
grant execute on function list_tenant_members(uuid),manage_tenant_member(uuid,uuid,text) to authenticated;
