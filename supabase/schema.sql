-- Run once in a NEW Supabase project, using its SQL Editor as project owner.
-- Auth users are created in Authentication > Users. Never put service_role in the app.
begin;
create table public.stores (
  id uuid primary key default gen_random_uuid(), name text not null
);
create table public.memberships (
  store_id uuid not null references public.stores(id),
  user_id uuid not null references auth.users(id),
  role text not null check(role in ('admin','operator')),
  primary key(store_id,user_id)
);
create table public.entities (
  store_id uuid not null references public.stores(id),
  kind text not null check(kind in ('product','consumption')),
  id uuid not null,
  code text,
  version integer not null check(version>0),
  body jsonb not null,
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  revision bigserial not null,
  primary key(store_id,kind,id)
);
create unique index product_code_unique on public.entities(store_id,code) where kind='product';
create index consumption_date on public.entities(store_id,(body->>'date')) where kind='consumption';
create index entities_sync_revision on public.entities(store_id,revision);
create table public.operations (
  store_id uuid not null references public.stores(id),
  id uuid not null, device_id uuid not null, actor uuid not null references auth.users(id),
  entity_id uuid not null, kind text not null, expected_version integer not null,
  request_hash text not null, received_at timestamptz not null default now(),
  primary key(store_id,id)
);
create table public.export_batches (
  store_id uuid not null references public.stores(id), id uuid not null,
  created_at timestamptz not null default now(), created_by uuid not null references auth.users(id),
  body jsonb not null, primary key(store_id,id)
);
create table public.export_items (
  store_id uuid not null, consumption_id uuid not null, item_id uuid not null, batch_id uuid not null,
  primary key(store_id,consumption_id,item_id),
  foreign key(store_id,batch_id) references public.export_batches(store_id,id)
);
alter table public.export_batches enable row level security;
alter table public.export_items enable row level security;
revoke all on public.export_batches,public.export_items from anon,authenticated;
grant select on public.export_batches to authenticated;
create policy admin_batches on public.export_batches for select to authenticated using(exists(
  select 1 from public.memberships m where m.store_id=export_batches.store_id and m.user_id=auth.uid() and m.role='admin'));

alter table public.stores enable row level security;
alter table public.memberships enable row level security;
alter table public.entities enable row level security;
alter table public.operations enable row level security;
revoke all on public.stores,public.memberships,public.entities,public.operations from anon,authenticated;
grant select on public.stores,public.memberships,public.entities to authenticated;
create policy self_memberships on public.memberships for select to authenticated using(user_id=auth.uid());
create policy member_store on public.stores for select to authenticated using(exists(
  select 1 from public.memberships m where m.store_id=stores.id and m.user_id=auth.uid()));
create policy member_entities on public.entities for select to authenticated using(exists(
  select 1 from public.memberships m where m.store_id=entities.store_id and m.user_id=auth.uid()
    and (entities.kind='product' or m.role='admin' or entities.created_by=auth.uid())));

create function public.apply_operation(p_store uuid,p_operation uuid,p_device uuid,
  p_kind text,p_expected integer,p_body jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_role text; v_actor uuid:=auth.uid(); v_id uuid; v_current public.entities;
  v_previous public.operations; v_item jsonb; v_product jsonb;
  v_amount bigint; v_total bigint; v_hash text;
begin
  if v_actor is null then raise exception 'Autenticação necessária'; end if;
  select role into v_role from public.memberships where store_id=p_store and user_id=v_actor;
  if v_role is null then raise exception 'Usuário sem acesso à loja'; end if;
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
      if v_product is null or v_product->>'active'<>'true' or v_product->>'unit'<>v_item->>'unit' then raise exception 'Produto inexistente, inativo ou unidade alterada'; end if;
      if length(trim(coalesce(v_item->>'code',''))) not between 1 and 40 or length(trim(coalesce(v_item->>'description',''))) not between 1 and 150 then raise exception 'Identificação do item inválida'; end if;
    end loop;
  else
    if v_role<>'admin' then raise exception 'Somente administradores cancelam'; end if;
    if jsonb_typeof(p_body->'cancellation_reason') is distinct from 'string' then raise exception 'Justificativa inválida'; end if;
    if exists(select 1 from public.export_items where store_id=p_store and consumption_id=v_id) then
      raise exception 'Consumo já incluído em lote. A correção exige revisão do lote com o administrador'; end if;
    if v_current.body->>'status'<>'confirmed' or coalesce(p_body->>'status','')<>'cancelled' or
      length(trim(coalesce(p_body->>'cancellation_reason',''))) not between 3 and 300 then raise exception 'Cancelamento inválido'; end if;
    if (v_current.body - array['status','version','cancellation_reason','cancelled_at']) <>
       (p_body - array['status','version','cancellation_reason','cancelled_at']) then raise exception 'Dados históricos não podem ser alterados'; end if;
  end if;
  insert into public.entities(store_id,kind,id,code,version,body,created_by)
  values(p_store,p_kind,v_id,case when p_kind='product' then p_body->>'code' end,p_expected+1,p_body,v_actor)
  on conflict(store_id,kind,id) do update set code=excluded.code,version=excluded.version,body=excluded.body,updated_at=now(),revision=nextval('public.entities_revision_seq');
  insert into public.operations(store_id,id,device_id,actor,entity_id,kind,expected_version,request_hash)
  values(p_store,p_operation,p_device,v_actor,v_id,p_kind,p_expected,v_hash);
  return jsonb_build_object('ok',true,'version',p_expected+1);
end $$;
revoke all on function public.apply_operation(uuid,uuid,uuid,text,integer,jsonb) from public,anon;
grant execute on function public.apply_operation(uuid,uuid,uuid,text,integer,jsonb) to authenticated;

create function public.create_export_batch(p_store uuid,p_id uuid,p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_request jsonb; v_entity public.entities; v_item jsonb;
  v_rows jsonb:='[]'; v_body jsonb; v_hash text;
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
    select value into v_item from jsonb_array_elements(v_entity.body->'items') where value->>'id'=v_request->>'item_id';
    if v_item is null then raise exception 'Item não encontrado'; end if;
    if exists(select 1 from public.export_items where store_id=p_store and consumption_id=v_entity.id and item_id=(v_item->>'id')::uuid) then raise exception 'Item já pertence a um lote'; end if;
    v_rows:=v_rows||jsonb_build_array(jsonb_build_object('consumption',v_entity.body,'item',v_item));
  end loop;
  v_body:=jsonb_build_object('id',p_id,'created_at',now(),'status','prepared','version',1,'request_hash',v_hash,'rows',v_rows);
  insert into public.export_batches(store_id,id,created_by,body) values(p_store,p_id,v_actor,v_body);
  for v_request in select value from jsonb_array_elements(p_items) loop
    insert into public.export_items values(p_store,(v_request->>'consumption_id')::uuid,(v_request->>'item_id')::uuid,p_id);
  end loop;
  return v_body;
end $$;
revoke all on function public.create_export_batch(uuid,uuid,jsonb) from public,anon;
grant execute on function public.create_export_batch(uuid,uuid,jsonb) to authenticated;

create function public.update_export_batch(p_store uuid,p_id uuid,p_version integer,p_action text,p_reference text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_body jsonb;
begin
  if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and role='admin') then
    raise exception 'Somente administradores alteram lotes'; end if;
  if p_version is null or p_version<1 or p_action is null or p_action not in ('issued','cancelled') or length(trim(coalesce(p_reference,''))) not between 3 and 200 then
    raise exception 'Informe uma referência de emissão ou justificativa com 3 a 200 caracteres'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
  select body into v_body from public.export_batches where store_id=p_store and id=p_id;
  if v_body is null then raise exception 'Lote inexistente'; end if;
  if v_body->>'status'=p_action and v_body->>'reference'=trim(p_reference) then return v_body; end if;
  if v_body->>'status'<>'prepared' or (v_body->>'version')::integer<>p_version then raise exception 'Lote alterado. Sincronize e confira o estado atual'; end if;
  v_body:=v_body||jsonb_build_object('status',p_action,'version',p_version+1,'reference',trim(p_reference),'updated_at',now(),'updated_by',auth.uid());
  update public.export_batches set body=v_body where store_id=p_store and id=p_id;
  if p_action='cancelled' then delete from public.export_items where store_id=p_store and batch_id=p_id; end if;
  return v_body;
end $$;
revoke all on function public.update_export_batch(uuid,uuid,integer,text,text) from public,anon;
grant execute on function public.update_export_batch(uuid,uuid,integer,text,text) to authenticated;
commit;

-- Bootstrap (replace IDs after creating Auth users):
-- insert into public.stores(name) values('Meu supermercado') returning id;
-- insert into public.memberships(store_id,user_id,role)
-- values('ID_DA_LOJA','ID_DO_USUARIO_AUTH','admin');
-- Use role 'operator' for employees. Never grant table writes to authenticated/anon.
