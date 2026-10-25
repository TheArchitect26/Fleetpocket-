-- A private object path is not an authorisation credential. Customer uploaders
-- may register only objects owned by their Auth identity, even if another path is known.
create or replace function guard_document_evidence() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if TG_OP='INSERT' and auth.uid() is not null and not has_tenant(new.tenant_id,false,true) then
  if not exists(select 1 from storage.objects where bucket_id='fleet-documents' and name=new.path and owner_id=auth.uid()::text) then
   raise exception using errcode='42501',message='Register only your own uploaded file';
  end if;
 end if;
 if TG_OP='UPDATE' and (new.path,new.kind,new.vehicle_id,new.job_id,new.uploaded_by) is distinct from (old.path,old.kind,old.vehicle_id,old.job_id,old.uploaded_by) then
  raise exception using errcode='23514',message='Document evidence is immutable; upload a new version';
 end if;
 if new.kind='Proof of delivery' and (new.job_id is null or not exists(select 1 from jobs where id=new.job_id and tenant_id=new.tenant_id and vehicle_id=new.vehicle_id)) then
  raise exception using errcode='23514',message='POD must match its job and vehicle';
 end if;
 return new;
end $$;
revoke all on function guard_document_evidence() from public,anon,authenticated;
