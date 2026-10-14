-- Execute após 007. Preserva códigos e aparelhos existentes.
-- Cada código adicional ativa uma única instalação do mesmo setor.
begin;
alter table public.sector_devices add column id uuid not null default gen_random_uuid();
alter table public.sector_devices drop constraint sector_devices_pkey;
alter table public.sector_devices add primary key(id);
create index sector_devices_store_slot on public.sector_devices(store_id,slot);
-- Administrative recovery remains a single slot and is provisioned only by the owner.
create unique index sector_devices_one_admin on public.sector_devices(store_id) where slot='admin';
create or replace function public.provision_sector_device(p_store uuid,p_slot text,p_replace boolean default false)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_old public.sector_devices%rowtype;v_code text;v_id uuid;
begin
 if p_store is null then raise exception 'Informe a loja';end if;
 if p_replace is null then raise exception 'Confirme a substituição explicitamente';end if;
 if p_slot is null or p_slot not in ('admin','hortifruti','cozinha','padaria') then raise exception 'Setor inválido';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
 -- A sector may have multiple devices. Never revoke all of them by sector.
 if p_slot<>'admin' and p_replace then
   raise exception 'Revogue somente o aparelho desejado em Administração e gere um novo código sem substituição';
 end if;
 if p_slot='admin' then
   select * into v_old from public.sector_devices where store_id=p_store and slot='admin';
   if v_old.actor is not null and not p_replace then raise exception 'Aparelho administrativo já ativado. Substituição exige confirmação e backup';end if;
   if v_old.actor is not null then
     delete from public.memberships where store_id=p_store and user_id=v_old.actor;
   end if;
 end if;
 v_code:=upper(replace(gen_random_uuid()::text,'-',''));
 if v_old.id is not null then
   update public.sector_devices set actor=null,device_id=null,activated_at=null,
     code_hash=encode(sha256(convert_to(v_code,'UTF8')),'hex'),expires_at=clock_timestamp()+interval '24 hours'
     where id=v_old.id returning id into v_id;
 else
   insert into public.sector_devices(store_id,slot,code_hash,expires_at)
   values(p_store,p_slot,encode(sha256(convert_to(v_code,'UTF8')),'hex'),clock_timestamp()+interval '24 hours')
   returning id into v_id;
 end if;
 return jsonb_build_object('id',v_id,'slot',p_slot,'code',v_code,'expires_in_hours',24);
end $$;
revoke all on function public.provision_sector_device(uuid,text,boolean) from public,anon,authenticated;

create or replace function public.admin_provision_sector(p_store uuid,p_slot text,p_replace boolean,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_result jsonb;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
 if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and role='admin') then raise exception 'Acesso administrativo obrigatório';end if;
 if p_slot is null or p_slot not in ('hortifruti','cozinha','padaria') then raise exception 'Administrador só é provisionado no SQL Editor';end if;
 if length(trim(coalesce(p_reason,''))) not between 3 and 300 then raise exception 'Informe justificativa';end if;
 v_result:=public.provision_sector_device(p_store,p_slot,p_replace);
 insert into public.audit_log(store_id,source_key,actor,sector,action,detail)
 values(p_store,'device-code:'||gen_random_uuid(),auth.uid(),p_slot,'device_code_issued',jsonb_build_object('replaced',p_replace,'reason',p_reason));
 return v_result;
end $$;
revoke all on function public.admin_provision_sector(uuid,text,boolean,text) from public,anon;
grant execute on function public.admin_provision_sector(uuid,text,boolean,text) to authenticated;

create or replace function public.activate_sector_device(p_store uuid,p_device uuid,p_code text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_slot public.sector_devices%rowtype;v_code text;v_role text;
begin
 if auth.uid() is null or p_device is null then raise exception 'Autentique o aparelho';end if;
 v_code:=upper(replace(trim(coalesce(p_code,'')),'-',''));
 if v_code !~ '^[0-9A-F]{32}$' then raise exception 'Código de ativação inválido';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
 select * into v_slot from public.sector_devices where store_id=p_store and code_hash=encode(sha256(convert_to(v_code,'UTF8')),'hex');
 if not found then raise exception 'Código de ativação inválido';end if;
 -- A lost response can replay only on the same account AND same installation.
 if v_slot.actor is not null then
   if v_slot.actor=auth.uid() and v_slot.device_id=p_device and exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid()) then
     return jsonb_build_object('activated',true,'slot',v_slot.slot,'duplicate',true);
   end if;
   raise exception 'Código já utilizado por outro aparelho';
 end if;
 if v_slot.expires_at<clock_timestamp() then raise exception 'Código de ativação expirado';end if;
 if exists(select 1 from public.sector_devices where store_id=p_store and actor=auth.uid()) then raise exception 'Aparelho já vinculado a outro setor';end if;
 v_role:=case when v_slot.slot='admin' then 'admin' else 'operator' end;
 if exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and (role<>v_role or sector is distinct from case when v_role='admin' then null else v_slot.slot end)) then raise exception 'O vínculo existente não pode mudar de papel ou setor';end if;
 insert into public.memberships(store_id,user_id,role,sector,features_version)
 values(p_store,auth.uid(),v_role,case when v_role='admin' then null else v_slot.slot end,7)
 on conflict(store_id,user_id)do update set features_version=7;
 update public.sector_devices set actor=auth.uid(),device_id=p_device,activated_at=clock_timestamp() where id=v_slot.id;
 insert into public.audit_log(store_id,source_key,actor,device_id,sector,action,detail)
 values(p_store,'device-activation:'||gen_random_uuid(),auth.uid(),p_device,case when v_role='admin' then null else v_slot.slot end,'device_activated',jsonb_build_object('slot',v_slot.slot));
 return jsonb_build_object('activated',true,'slot',v_slot.slot);
end $$;
revoke all on function public.activate_sector_device(uuid,uuid,text) from public,anon;
grant execute on function public.activate_sector_device(uuid,uuid,text) to authenticated;

-- Once activated, the server enforces a fixed role/sector even through old admin APIs.
create or replace function public.enforce_device_membership()returns trigger language plpgsql set search_path=public,pg_temp as $$
declare v_slot text;
begin
 select slot into v_slot from public.sector_devices where store_id=new.store_id and actor=new.user_id;
 if found and (new.role is distinct from case when v_slot='admin' then 'admin' else 'operator' end or new.sector is distinct from case when v_slot='admin' then null else v_slot end) then raise exception 'Papel e setor do aparelho ativado são fixos';end if;
 return new;
end $$;
notify pgrst,'reload schema';
commit;

