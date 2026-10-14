-- Consumo Interno 1.7.6: execute após 009, como proprietário no SQL Editor.
-- Mantém somente as duas cópias mais recentes por loja/identidade/aparelho.
-- Remove as cópias antigas excedentes; não altera produtos ou consumos.
begin;
create or replace function public.upload_device_backup(p_store uuid,p_device uuid,p_hash text,p_payload text)returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and (role='admin' or sector is not null))then raise exception 'Conta não autorizada';end if;
 if p_payload is null or octet_length(decode(p_payload,'base64'))>20971520 or encode(sha256(decode(p_payload,'base64')),'hex')is distinct from p_hash then raise exception 'Backup inválido ou acima de 20 MB comprimidos';end if;
 -- Serialize uploads for this store/identity/device so concurrent uploads keep the limit.
 perform pg_advisory_xact_lock(hashtextextended(p_store::text||':'||auth.uid()::text||':'||p_device::text,1));
 insert into public.device_backups(store_id,actor,device_id,scope_role,sector,hash,payload)values(p_store,auth.uid(),p_device,(select role from public.memberships where store_id=p_store and user_id=auth.uid()),(select sector from public.memberships where store_id=p_store and user_id=auth.uid()),p_hash,p_payload)on conflict do nothing;
 delete from public.device_backups where store_id=p_store and actor=auth.uid()and device_id=p_device and hash in(select hash from public.device_backups where store_id=p_store and actor=auth.uid()and device_id=p_device order by revision desc offset 2);
end $$;
revoke all on function public.upload_device_backup(uuid,uuid,text,text) from public,anon;
grant execute on function public.upload_device_backup(uuid,uuid,text,text) to authenticated;
-- Wait for in-flight writes and prevent inserts while applying the new retention.
lock table public.device_backups in share row exclusive mode;
with ranked as (
 select store_id,actor,device_id,hash,
   row_number() over(partition by store_id,actor,device_id order by revision desc) as rn
 from public.device_backups
)
delete from public.device_backups b using ranked r
where b.store_id=r.store_id and b.actor=r.actor and b.device_id=r.device_id
  and b.hash=r.hash and r.rn>2;
notify pgrst,'reload schema';
commit;
