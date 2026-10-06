-- Execute após 006. Ativação por aparelho, sem e-mail. Habilite Anonymous Sign-Ins.
begin;
create table public.sector_devices (
 store_id uuid not null references public.stores(id),
 slot text not null check(slot in ('admin','hortifruti','cozinha','padaria')),
 actor uuid references auth.users(id),device_id uuid,
 code_hash text not null,expires_at timestamptz not null,
 activated_at timestamptz,
 primary key(store_id,slot),unique(store_id,actor),unique(store_id,device_id),unique(store_id,code_hash)
);
alter table public.sector_devices enable row level security;
revoke all on public.sector_devices from public,anon,authenticated;

-- SQL Editor/project owner only: initial administrator and recovery provisioning.
create or replace function public.provision_sector_device(p_store uuid,p_slot text,p_replace boolean default false)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_old public.sector_devices%rowtype;v_code text;
begin
 if p_replace is null then raise exception 'Confirme a substituição explicitamente';end if;
 if p_slot is null or p_slot not in ('admin','hortifruti','cozinha','padaria') then raise exception 'Setor inválido';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
 select * into v_old from public.sector_devices where store_id=p_store and slot=p_slot;
 if v_old.actor is not null and not p_replace then raise exception 'Aparelho já ativado. Substituição exige confirmação e backup';end if;
 if v_old.actor is not null then
   delete from public.memberships where store_id=p_store and user_id=v_old.actor;
 end if;
 v_code:=upper(replace(gen_random_uuid()::text,'-',''));
 insert into public.sector_devices(store_id,slot,code_hash,expires_at)
 values(p_store,p_slot,encode(sha256(convert_to(v_code,'UTF8')),'hex'),clock_timestamp()+interval '24 hours')
 on conflict(store_id,slot)do update set actor=null,device_id=null,activated_at=null,
 code_hash=excluded.code_hash,expires_at=excluded.expires_at;
 return jsonb_build_object('slot',p_slot,'code',v_code,'expires_in_hours',24);
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
 if v_slot.slot<>'admin' and exists(select 1 from public.memberships where store_id=p_store and role='operator' and sector=v_slot.slot and user_id<>auth.uid()) then raise exception 'Revogue os vínculos antigos deste setor antes de ativar';end if;
 v_role:=case when v_slot.slot='admin' then 'admin' else 'operator' end;
 if exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and (role<>v_role or sector is distinct from case when v_role='admin' then null else v_slot.slot end)) then raise exception 'O vínculo existente não pode mudar de papel ou setor';end if;
 insert into public.memberships(store_id,user_id,role,sector,features_version)
 values(p_store,auth.uid(),v_role,case when v_role='admin' then null else v_slot.slot end,7)
 on conflict(store_id,user_id)do update set features_version=7;
 update public.sector_devices set actor=auth.uid(),device_id=p_device,activated_at=clock_timestamp() where store_id=p_store and slot=v_slot.slot;
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
 if new.role='operator' and exists(select 1 from public.sector_devices where store_id=new.store_id and slot=new.sector and actor is not null and actor<>new.user_id) then raise exception 'Este setor já possui um aparelho ativo';end if;
 return new;
end $$;
create trigger device_membership_fixed before insert or update on public.memberships for each row execute function public.enforce_device_membership();
notify pgrst,'reload schema';
commit;
