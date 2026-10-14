-- Execute após 010. Lista de aparelhos exclusiva da administração.
begin;
create or replace function public.admin_members(p_store uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and role='admin') then
   raise exception 'Acesso administrativo obrigatório';
 end if;
 return coalesce((
   select jsonb_agg(jsonb_build_object(
     'user_id',m.user_id,'role',m.role,'sector',m.sector,
     'device_id',d.device_id,'activated_at',d.activated_at
   ) order by m.role,m.sector nulls first,m.user_id)
   from public.memberships m
   left join public.sector_devices d on d.store_id=m.store_id and d.actor=m.user_id
   where m.store_id=p_store
 ),'[]'::jsonb);
end $$;
revoke all on function public.admin_members(uuid) from public,anon;
grant execute on function public.admin_members(uuid) to authenticated;
notify pgrst,'reload schema';
commit;

