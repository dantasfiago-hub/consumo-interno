-- Atualização 1.3: executar após 002_exports_v2.sql. Sem apagar dados.
begin;
create or replace function public.sector_key(value text) returns text language sql immutable as $$
  select case lower(regexp_replace(coalesce(value,''),'[[:space:]_-]','','g'))
    when 'hortifruti' then 'hortifruti' when 'cozinha' then 'cozinha' when 'padaria' then 'padaria' end
$$;
alter table public.memberships add column if not exists sector text check(sector is null or sector in ('hortifruti','cozinha','padaria'));
alter table public.entities add column if not exists sector_id text check(sector_id is null or sector_id in ('hortifruti','cozinha','padaria'));
alter table public.entities add column if not exists export_locked boolean not null default false;
update public.entities set sector_id=public.sector_key(body->>'sector'),revision=nextval('public.entities_revision_seq') where kind='consumption' and sector_id is null;
update public.entities e set export_locked=true,revision=nextval('public.entities_revision_seq') where kind='consumption' and exists(select 1 from public.export_items i where i.store_id=e.store_id and i.consumption_id=e.id) and not export_locked;
drop policy if exists member_entities on public.entities;
create policy member_entities on public.entities for select to authenticated using(exists(
  select 1 from public.memberships m where m.store_id=entities.store_id and m.user_id=auth.uid()
    and (m.role='admin' or m.sector is not null and
      (entities.kind='product' and coalesce(entities.body->'sectors','[]'::jsonb) ? m.sector
       or entities.kind='consumption' and entities.sector_id=m.sector))));
create index if not exists consumption_sector on public.entities(store_id,sector_id) where kind='consumption';

create or replace function public.track_export_lock() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_store uuid; v_consumption uuid; v_locked boolean;
begin
  if TG_OP='DELETE' then v_store:=OLD.store_id; v_consumption:=OLD.consumption_id;
  else v_store:=NEW.store_id; v_consumption:=NEW.consumption_id; end if;
  v_locked:=exists(select 1 from public.export_items where store_id=v_store and consumption_id=v_consumption);
  update public.entities set export_locked=v_locked,revision=nextval('public.entities_revision_seq')
    where store_id=v_store and kind='consumption' and id=v_consumption and export_locked is distinct from v_locked;
  return null;
end $$;
revoke all on function public.track_export_lock() from public,anon,authenticated;
drop trigger if exists export_lock on public.export_items;
create trigger export_lock after insert or delete on public.export_items for each row execute function public.track_export_lock();
create or replace function public.apply_operation(p_store uuid,p_operation uuid,p_device uuid,
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
      if v_product is null or not coalesce(v_product->'sectors','[]'::jsonb) ? v_target_sector or v_product->>'active'<>'true' or v_product->>'unit'<>v_item->>'unit' then raise exception 'Produto inexistente, inativo ou unidade alterada'; end if;
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
revoke all on function public.apply_operation(uuid,uuid,uuid,text,integer,jsonb) from public,anon;
grant execute on function public.apply_operation(uuid,uuid,uuid,text,integer,jsonb) to authenticated;

create or replace function public.create_export_batch(p_store uuid,p_id uuid,p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_request jsonb; v_entity public.entities; v_item jsonb;
  v_sector text; v_rows jsonb:='[]'; v_body jsonb; v_hash text;
begin
  if not exists(select 1 from public.memberships where store_id=p_store and user_id=v_actor and role='admin') then raise exception 'Somente administradores exportam lotes'; end if;
  if p_id is null or jsonb_typeof(p_items) is distinct from 'array' then raise exception 'Seleção inválida'; end if;
  if jsonb_array_length(p_items) not between 1 and 2000 then raise exception 'Selecione entre 1 e 2000 itens'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
  v_hash:=md5(p_items::text);
  select body into v_body from public.export_batches where store_id=p_store and id=p_id;
  if found then
    if v_body->>'request_hash'<>v_hash then raise exception 'Identificador de lote reutilizado'; end if;
    return v_body;
  end if;
  for v_request in select value from jsonb_array_elements(p_items) loop
    select * into v_entity from public.entities where store_id=p_store and kind='consumption' and id=(v_request->>'consumption_id')::uuid;
    if v_entity.id is null or v_entity.body->>'status'<>'confirmed' or v_entity.version<>coalesce((v_request->>'version')::integer,0) then raise exception 'Consumo alterado. Sincronize antes de fechar o lote'; end if;
    if v_entity.sector_id is null then raise exception 'Defina o setor dos consumos antigos antes de exportar'; end if;
    if v_sector is null then v_sector:=v_entity.sector_id; elsif v_sector<>v_entity.sector_id then raise exception 'Cada arquivo deve conter um único setor'; end if;
    select value into v_item from jsonb_array_elements(v_entity.body->'items') where value->>'id'=v_request->>'item_id';
    if v_item is null then raise exception 'Item não encontrado'; end if;
    if exists(select 1 from public.export_items where store_id=p_store and consumption_id=v_entity.id and item_id=(v_item->>'id')::uuid) then raise exception 'Item já pertence a um lote'; end if;
    v_rows:=v_rows||jsonb_build_array(jsonb_build_object('consumption',v_entity.body,'item',v_item));
  end loop;
  v_body:=jsonb_build_object('id',p_id,'created_at',now(),'status','prepared','version',1,'request_hash',v_hash,'rows',v_rows,'sector',v_sector);
  insert into public.export_batches(store_id,id,created_by,body) values(p_store,p_id,v_actor,v_body);
  for v_request in select value from jsonb_array_elements(p_items) loop
    insert into public.export_items values(p_store,(v_request->>'consumption_id')::uuid,(v_request->>'item_id')::uuid,p_id);
  end loop;
  return v_body;
end $$;
revoke all on function public.create_export_batch(uuid,uuid,jsonb) from public,anon;
grant execute on function public.create_export_batch(uuid,uuid,jsonb) to authenticated;


create or replace function public.create_export_batch_v3(p_store uuid,p_id uuid,p_items jsonb,p_profile jsonb,p_filters jsonb,p_sector text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_hash text; v_existing jsonb; v_available jsonb; v_body jsonb;
begin
  if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and role='admin') then raise exception 'Somente administradores exportam'; end if;
  if p_sector is null or p_sector not in ('hortifruti','cozinha','padaria') or jsonb_typeof(p_items) is distinct from 'array' then raise exception 'Selecione um setor e os itens'; end if;
  if jsonb_array_length(p_items) not between 1 and 2000 then raise exception 'Selecione entre 1 e 2000 itens'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
  v_hash:=encode(sha256(convert_to(jsonb_build_object('items',p_items,'profile',p_profile,'filters',p_filters,'sector',p_sector)::text,'UTF8')),'hex');
  select body into v_existing from public.export_batches where store_id=p_store and id=p_id;
  if found then
    if v_existing->>'sector_request_hash' is distinct from v_hash then raise exception 'Identificador de lote reutilizado'; end if;
    return v_existing;
  end if;
  -- Excluir exportados/reservados é feito no servidor, sob o mesmo lock da reserva.
  if exists(select 1 from jsonb_array_elements(p_items) r left join public.entities e
    on e.store_id=p_store and e.kind='consumption' and e.id=(r->>'consumption_id')::uuid
    where e.id is null or e.sector_id is distinct from p_sector) then raise exception 'Cada arquivo deve conter somente consumos do setor selecionado'; end if;
  select coalesce(jsonb_agg(r order by r->>'consumption_id',r->>'item_id'),'[]'::jsonb) into v_available
    from jsonb_array_elements(p_items) r where not exists(select 1 from public.export_items i
      where i.store_id=p_store and i.consumption_id=(r->>'consumption_id')::uuid and i.item_id=(r->>'item_id')::uuid);
  if jsonb_array_length(v_available)=0 then raise exception 'Todos os itens selecionados já estão exportados ou reservados. Atualize a consulta'; end if;
  v_body:=public.create_export_batch_v2(p_store,p_id,v_available,p_profile,p_filters||jsonb_build_object('sector',p_sector));
  v_body:=v_body||jsonb_build_object('sector',p_sector,'sector_request_hash',v_hash,
    'skipped_count',jsonb_array_length(p_items)-jsonb_array_length(v_available),'requested_item_count',jsonb_array_length(p_items));
  v_body:=jsonb_set(v_body,'{artifact,name}',to_jsonb('consumo_'||p_sector||'_'||p_id||'.txt'));
  update public.export_batches set body=v_body where store_id=p_store and id=p_id;
  return v_body;
end $$;
revoke all on function public.create_export_batch_v3(uuid,uuid,jsonb,jsonb,jsonb,text) from public,anon;
grant execute on function public.create_export_batch_v3(uuid,uuid,jsonb,jsonb,jsonb,text) to authenticated;

create or replace function public.assign_legacy_sector(p_store uuid,p_id uuid,p_sector text,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and role='admin') then raise exception 'Somente administradores classificam registros antigos'; end if;
  if p_sector is null or p_sector not in ('hortifruti','cozinha','padaria') or length(trim(coalesce(p_reason,''))) not between 3 and 200 then raise exception 'Informe setor e justificativa'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
  if exists(select 1 from public.entities where store_id=p_store and kind='consumption' and id=p_id and sector_id=p_sector) then return; end if;
  update public.entities set sector_id=p_sector,revision=nextval('public.entities_revision_seq')
    where store_id=p_store and kind='consumption' and id=p_id and sector_id is null and not export_locked;
  if not found then raise exception 'Somente registros antigos sem setor e sem exportação podem ser classificados'; end if;
  insert into public.operations(store_id,id,device_id,actor,entity_id,kind,expected_version,request_hash)
    values(p_store,gen_random_uuid(),gen_random_uuid(),auth.uid(),p_id,'assign_legacy_sector',0,p_sector||':'||trim(p_reason));
end $$;
revoke all on function public.assign_legacy_sector(uuid,uuid,text,text) from public,anon;
grant execute on function public.assign_legacy_sector(uuid,uuid,text,text) to authenticated;
notify pgrst, 'reload schema';
commit;
