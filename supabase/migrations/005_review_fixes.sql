-- Correções de revisão 1.4.1: aplicar depois de 004. Preserva hashes e histórico.
begin;
create or replace function public.apply_operation_checked(p_store uuid,p_operation uuid,p_device uuid,
  p_kind text,p_expected integer,p_body jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_role text; v_sector text; v_target_sector text; v_actor uuid:=auth.uid(); v_id uuid; v_current public.entities;
  v_previous public.operations; v_item jsonb; v_product jsonb;
  v_amount bigint; v_total bigint; v_hash text;
begin
  if v_actor is null then raise exception 'Autenticação necessária'; end if;
  select role,sector into v_role,v_sector from public.memberships where store_id=p_store and user_id=v_actor;
  if v_role is null then raise exception 'Usuário sem acesso à loja'; end if;
  if v_role='operator' and v_sector is null then raise exception 'Conta sem setor. Peça ao administrador para vincular a conta'; end if;
  p_body:=p_body-array['_owner','_sector_id','_export_locked'];
  if p_kind is null or p_kind not in ('product','consumption') or p_expected is null or p_expected<0 then
    raise exception 'Operação inválida'; end if;
  if p_operation is null or p_device is null or jsonb_typeof(p_body) is distinct from 'object' then
    raise exception 'Identificadores ou conteúdo inválidos'; end if;
  if octet_length(p_body::text)>2000000 or jsonb_typeof(p_body->'id') is distinct from 'string' or
    jsonb_typeof(p_body->'version') is distinct from 'number' then raise exception 'Conteúdo ou tipos inválidos'; end if;
  v_id:=(p_body->>'id')::uuid;
  if v_id is null then raise exception 'ID obrigatório'; end if;
  -- Serialize operations per store: consistent idempotency and version checks, including inserts.
  perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
  v_hash:=md5(jsonb_build_object('kind',p_kind,'expected',p_expected,'body',p_body)::text);
  select * into v_previous from public.operations where store_id=p_store and id=p_operation;
  if found then
    if v_previous.actor<>v_actor or v_previous.request_hash<>v_hash then raise exception 'ID de operação reutilizado com outro conteúdo'; end if;
    return jsonb_build_object('ok',true,'duplicate',true);
  end if;
  select * into v_current from public.entities where store_id=p_store and kind=p_kind and id=v_id;
  if coalesce(v_current.version,0)<>p_expected then raise exception 'Conflito de versão. Revise o registro antes de reenviar'; end if;
  if coalesce((p_body->>'version')::integer,0)<>p_expected+1 then raise exception 'Versão inválida'; end if;
  if p_kind='product' then
    if v_role<>'admin' then raise exception 'Somente administradores alteram produtos'; end if;
    if p_body ? 'sectors' then
      if jsonb_typeof(p_body->'sectors') is distinct from 'array' then raise exception 'Setores do produto inválidos'; end if;
      if jsonb_array_length(p_body->'sectors')>3 or exists(select 1 from jsonb_array_elements_text(p_body->'sectors') s where s not in ('hortifruti','cozinha','padaria')) or
        (select count(distinct value) from jsonb_array_elements_text(p_body->'sectors'))<>jsonb_array_length(p_body->'sectors') then raise exception 'Setores do produto inválidos'; end if;
    end if;
    if jsonb_typeof(p_body->'code') is distinct from 'string' or jsonb_typeof(p_body->'description') is distinct from 'string' or
      jsonb_typeof(p_body->'unit') is distinct from 'string' or
      coalesce(jsonb_typeof(p_body->'photo'),'null') not in ('null','string') then raise exception 'Tipos do produto inválidos'; end if;
    if length(trim(coalesce(p_body->>'code',''))) not between 1 and 40 or
       length(trim(coalesce(p_body->>'description',''))) not between 1 and 150 or
       coalesce(p_body->>'unit','') not in ('UN','KG') or
       jsonb_typeof(p_body->'active') is distinct from 'boolean' or
       length(coalesce(p_body->>'photo',''))>180000 then raise exception 'Produto inválido'; end if;
    if p_body->>'photo' is not null and (p_body->>'photo') !~ '^[A-Za-z0-9+/]*={0,2}$' then raise exception 'Foto inválida'; end if;
  elsif p_expected=0 then
    v_target_sector:=public.sector_key(p_body->>'sector');
    if v_target_sector is null or (v_role='operator' and v_target_sector<>v_sector) then raise exception 'Setor do consumo não autorizado'; end if;
    if jsonb_typeof(p_body->'operator') is distinct from 'string' or jsonb_typeof(p_body->'sector') is distinct from 'string' or
      jsonb_typeof(p_body->'note') is distinct from 'string' or jsonb_typeof(p_body->'date') is distinct from 'string' or
      jsonb_typeof(p_body->'created_at') is distinct from 'string' then raise exception 'Tipos do lançamento inválidos'; end if;
    if coalesce(p_body->>'status','')<>'confirmed' or
       length(trim(coalesce(p_body->>'operator',''))) not between 1 and 100 or
       length(coalesce(p_body->>'sector',''))>100 or length(coalesce(p_body->>'note',''))>500 or
       jsonb_typeof(p_body->'items') is distinct from 'array' then raise exception 'Lançamento inválido'; end if;
    if jsonb_array_length(p_body->'items') not between 1 and 200 then raise exception 'Informe entre 1 e 200 itens'; end if;
    if coalesce(p_body->>'date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Data inválida'; end if;
    perform (p_body->>'date')::date;
    if p_body->>'created_at' is null then raise exception 'Data de registro obrigatória'; end if;
    perform (p_body->>'created_at')::timestamptz;
    if (select count(distinct x->>'product_id') from jsonb_array_elements(p_body->'items') x)<>jsonb_array_length(p_body->'items') then
      raise exception 'Produtos repetidos'; end if;
    if (select count(distinct x->>'id') from jsonb_array_elements(p_body->'items') x)<>jsonb_array_length(p_body->'items') then
      raise exception 'IDs de itens repetidos'; end if;
    for v_item in select value from jsonb_array_elements(p_body->'items') loop
      if jsonb_typeof(v_item->'amount') is distinct from 'number' or jsonb_typeof(v_item->'total_cents') is distinct from 'number' or
        jsonb_typeof(v_item->'code') is distinct from 'string' or jsonb_typeof(v_item->'description') is distinct from 'string' then
        raise exception 'Tipos do item inválidos'; end if;
      if v_item->>'id' is null then raise exception 'ID de item obrigatório'; end if;
      perform (v_item->>'id')::uuid;
      if coalesce(v_item->>'amount','') !~ '^\d+$' or coalesce(v_item->>'total_cents','') !~ '^\d+$' then raise exception 'Valores devem ser inteiros na escala definida'; end if;
      v_amount:=(v_item->>'amount')::bigint; v_total:=(v_item->>'total_cents')::bigint;
      if v_amount not between 1 and 999999999999 or v_total not between 1 and 999999999999 or
        coalesce(v_item->>'unit','') not in ('UN','KG') or (v_item->>'unit'='UN' and v_amount%1000<>0) then raise exception 'Quantidade ou valor inválido'; end if;
      select body into v_product from public.entities where store_id=p_store and kind='product' and id=(v_item->>'product_id')::uuid;
      if v_product is null or not coalesce(v_product->'sectors','[]'::jsonb) ? v_target_sector or v_product->>'active'<>'true' or v_product->>'unit'<>v_item->>'unit' or v_product->>'code' is distinct from v_item->>'code' then raise exception 'Produto inexistente, inativo ou unidade alterada'; end if;
      if length(trim(coalesce(v_item->>'code',''))) not between 1 and 40 or length(trim(coalesce(v_item->>'description',''))) not between 1 and 150 then raise exception 'Identificação do item inválida'; end if;
    end loop;
  else
    if v_role<>'admin' and (v_current.sector_id is null or v_current.sector_id<>v_sector) then raise exception 'Você só pode cancelar consumos do seu setor'; end if;
    v_target_sector:=v_current.sector_id;
    if jsonb_typeof(p_body->'cancellation_reason') is distinct from 'string' then raise exception 'Justificativa inválida'; end if;
    if exists(select 1 from public.export_items where store_id=p_store and consumption_id=v_id) then
      raise exception 'Consumo já incluído em lote. A correção exige revisão do lote com o administrador'; end if;
    if v_current.body->>'status'<>'confirmed' or coalesce(p_body->>'status','')<>'cancelled' or
      length(trim(coalesce(p_body->>'cancellation_reason',''))) not between 3 and 300 then raise exception 'Cancelamento inválido'; end if;
    if (v_current.body - array['status','version','cancellation_reason','cancelled_at']) <>
       (p_body - array['status','version','cancellation_reason','cancelled_at']) then raise exception 'Dados históricos não podem ser alterados'; end if;
  end if;
  insert into public.entities(store_id,kind,id,code,version,body,created_by,sector_id)
  values(p_store,p_kind,v_id,case when p_kind='product' then p_body->>'code' end,p_expected+1,p_body,v_actor,v_target_sector)
  on conflict(store_id,kind,id) do update set sector_id=excluded.sector_id,code=excluded.code,version=excluded.version,body=excluded.body,updated_at=now(),revision=nextval('public.entities_revision_seq');
  insert into public.operations(store_id,id,device_id,actor,entity_id,kind,expected_version,request_hash)
  values(p_store,p_operation,p_device,v_actor,v_id,p_kind,p_expected,v_hash);
  return jsonb_build_object('ok',true,'version',p_expected+1);
end $$;
revoke all on function public.apply_operation_checked(uuid,uuid,uuid,text,integer,jsonb) from public,anon,authenticated;

create or replace function public.apply_operation(p_store uuid,p_operation uuid,p_device uuid,p_kind text,p_expected integer,p_body jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_result jsonb;v_photo text;v_hash text;v_wire jsonb;v_stored_hash text;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
  v_wire:=p_body;
  if p_kind='product' then
    if p_body->>'photo_hash' is not null and (jsonb_typeof(p_body->'photo_hash') is distinct from 'string' or p_body->>'photo_hash' !~ '^[0-9a-f]{64}$') then raise exception 'Hash de foto inválido';end if;
    v_photo:=p_body->>'photo';
    if v_photo is not null then
      if length(v_photo) not between 1 and 180000 then raise exception 'Foto inválida';end if;
      v_hash:=encode(sha256(decode(v_photo,'base64')),'hex');
      if p_body->>'photo_hash' is not null and p_body->>'photo_hash'<>v_hash then raise exception 'Hash de foto incompatível';end if;
      -- Older clients may already have committed either inline or separated media.
      -- Retry the exact historic body only when its complete request hash matches.
      select request_hash into v_stored_hash from public.operations where store_id=p_store and id=p_operation;
      if v_stored_hash is not null and v_stored_hash<>md5(jsonb_build_object('kind',p_kind,'expected',p_expected,'body',p_body-array['_owner','_sector_id','_export_locked'])::text) then
        v_wire:=(p_body-array['_owner','_sector_id','_export_locked'])||jsonb_build_object('photo',null,'photo_hash',v_hash);
        if v_stored_hash<>md5(jsonb_build_object('kind',p_kind,'expected',p_expected,'body',v_wire)::text) then v_wire:=p_body;end if;
      end if;
    end if;
  end if;
  v_result:=public.apply_operation_checked(p_store,p_operation,p_device,p_kind,p_expected,v_wire);
  if p_kind='product' and v_photo is not null then
    -- Never restore an old photo over a newer product version on duplicate replay.
    if exists(select 1 from public.entities where store_id=p_store and kind='product' and id=(p_body->>'id')::uuid and version=(p_body->>'version')::integer and (body->>'photo'=v_photo or body->>'photo_hash'=v_hash)) then
      insert into public.product_images(store_id,hash,data_base64,created_by)values(p_store,v_hash,v_photo,auth.uid())on conflict do nothing;
      update public.entities set body=body||jsonb_build_object('photo',null,'photo_hash',v_hash),revision=nextval('public.entities_revision_seq')where store_id=p_store and kind='product' and id=(p_body->>'id')::uuid and body->>'photo' is not null;
    end if;
  end if;
  return v_result;
end $$;
revoke all on function public.apply_operation(uuid,uuid,uuid,text,integer,jsonb) from public,anon;
grant execute on function public.apply_operation(uuid,uuid,uuid,text,integer,jsonb) to authenticated;
create or replace function public.upload_device_backup(p_store uuid,p_device uuid,p_hash text,p_payload text)returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and (role='admin' or sector is not null))then raise exception 'Conta não autorizada';end if;
 if p_payload is null or octet_length(decode(p_payload,'base64'))>20971520 or encode(sha256(decode(p_payload,'base64')),'hex')is distinct from p_hash then raise exception 'Backup inválido ou acima de 20 MB comprimidos';end if;
 insert into public.device_backups(store_id,actor,device_id,scope_role,sector,hash,payload)values(p_store,auth.uid(),p_device,(select role from public.memberships where store_id=p_store and user_id=auth.uid()),(select sector from public.memberships where store_id=p_store and user_id=auth.uid()),p_hash,p_payload)on conflict do nothing;
 delete from public.device_backups where store_id=p_store and actor=auth.uid()and device_id=p_device and hash in(select hash from public.device_backups where store_id=p_store and actor=auth.uid()and device_id=p_device order by revision desc offset 7);
end $$;
-- Migration 004 backfilled old operations using now(); preserve their true receipt dates.
update public.audit_log a set occurred_at=o.received_at
from public.operations o
where a.store_id=o.store_id
  and a.source_key='operation:'||o.store_id||':'||o.id
  and a.action='historical_'||o.kind;
notify pgrst,'reload schema';
commit;
