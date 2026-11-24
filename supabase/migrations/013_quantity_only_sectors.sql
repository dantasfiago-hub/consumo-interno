-- Execute após 012. Cozinha e Padaria registram somente quantidade: o valor total do item pode ser 0.
-- Horti Fruti continua exigindo valor positivo. O arquivo desses setores já contém só código e quantidade.
-- Idempotente: substitui duas funções por versões que aceitam total 0 nesses setores.
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
      if v_amount not between 1 and 999999999999 or v_total not between (case when v_target_sector in ('cozinha','padaria') then 0 else 1 end) and 999999999999 or
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

create or replace function public.create_export_batch_v2(p_store uuid,p_id uuid,p_items jsonb,p_profile jsonb,p_filters jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_body jsonb; v_existing jsonb; v_group record; v_rows jsonb:='[]';
  v_text text:=''; v_bytes bytea; v_sep text; v_decimal text; v_end text;
  v_quantity text; v_price text; v_field text; v_line text; v_code text;
  v_price4 numeric; v_hash text; v_profile jsonb;
begin
  if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and role='admin') then raise exception 'Somente administradores exportam lotes'; end if;
  if jsonb_typeof(p_profile) is distinct from 'object' or jsonb_typeof(p_filters) is distinct from 'object' or octet_length(p_filters::text)>2000 then raise exception 'Perfil ou filtros inválidos'; end if;
  if coalesce(p_profile->>'version','') !~ '^[1-9][0-9]{0,8}$' or
     coalesce(p_profile->>'separator','') not in (';','|',E'\t') or
     coalesce(p_profile->>'decimal','') not in (',','.') or
     coalesce(p_profile->>'encoding','') not in ('UTF8','LATIN1') or
     coalesce(p_profile->>'line_ending','') not in ('CRLF','LF') or
     jsonb_typeof(p_profile->'order') is distinct from 'array' or
     p_profile->'validated' is distinct from 'true'::jsonb then raise exception 'Confirme um perfil válido e conferido no VR Master'; end if;
  if not (
    (jsonb_array_length(p_profile->'order')=4 and
     (select count(distinct value) from jsonb_array_elements_text(p_profile->'order'))=4 and
     not exists(select 1 from jsonb_array_elements_text(p_profile->'order') where value not in ('code','quantity','unit','unit_price')))
    or (p_profile->'order'='["code","quantity"]'::jsonb and p_filters->>'sector' in ('cozinha','padaria'))
  ) then raise exception 'Ordem de campos inválida para o setor'; end if;
  if jsonb_typeof(p_profile->'header') is distinct from 'boolean' or
     jsonb_typeof(p_profile->'bom') is distinct from 'boolean' or
     jsonb_typeof(p_profile->'fixed_price') is distinct from 'boolean' or
     (p_profile->'bom'='true'::jsonb and p_profile->>'encoding'<>'UTF8') then raise exception 'Opções de perfil inválidas'; end if;
  v_profile:=p_profile;
  v_hash:=encode(sha256(convert_to(jsonb_build_object('items',p_items,'profile',v_profile,'filters',p_filters)::text,'UTF8')),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
  select body into v_existing from public.export_batches where store_id=p_store and id=p_id;
  if found then
    if v_existing->>'format_version'<>'2' or v_existing->>'export_request_hash' is distinct from v_hash then raise exception 'Identificador de lote reutilizado'; end if;
    return v_existing;
  end if;
  -- Validação de versões, snapshots e reservas fica na mesma transação.
  v_body:=public.create_export_batch(p_store,p_id,p_items);
  if exists(select 1 from jsonb_array_elements(v_body->'rows') r
    group by r->'item'->>'code'
    having count(distinct r->'item'->>'product_id')>1 or count(distinct r->'item'->>'unit')>1) then raise exception 'Código representa produtos ou unidades diferentes'; end if;
  v_sep:=v_profile->>'separator'; v_decimal:=v_profile->>'decimal';
  v_end:=case when v_profile->>'line_ending'='CRLF' then E'\r\n' else E'\n' end;
  if v_profile->'bom'='true'::jsonb then v_text:=chr(65279); end if;
  if v_profile->'header'='true'::jsonb then
    v_text:=v_text||(select string_agg(value,v_sep order by ord) from jsonb_array_elements_text(v_profile->'order') with ordinality f(value,ord))||v_end;
  end if;
  for v_group in
    select r->'item'->>'code' as code, min(r->'item'->>'description') as description,
      min(r->'item'->>'product_id') as product_id, min(r->'item'->>'unit') as measure,
      sum((r->'item'->>'amount')::numeric) as quantity,
      sum((r->'item'->>'total_cents')::numeric) as total
    from jsonb_array_elements(v_body->'rows') r group by r->'item'->>'code' order by (r->'item'->>'code') collate "C"
  loop
    v_code:=v_group.code;
    if strpos(v_code,v_sep)>0 or v_code ~ '[[:cntrl:]]' then raise exception 'Código contém caracteres incompatíveis com o arquivo'; end if;
    if v_group.quantity<=0 or v_group.total<0 or (v_group.total=0 and v_profile->'order' ? 'unit_price') then raise exception 'Quantidade e valor devem ser positivos'; end if;
    v_price4:=round(v_group.total*100000/v_group.quantity);
    v_quantity:=rtrim(rtrim(to_char(v_group.quantity/1000,'FM999999999999999999999999999990.000'),'0'),'.');
    v_price:=to_char(v_price4/10000,'FM999999999999999999999999999990.0000');
    if v_profile->'fixed_price'='false'::jsonb then v_price:=rtrim(rtrim(v_price,'0'),'.'); end if;
    v_quantity:=replace(v_quantity,'.',v_decimal); v_price:=replace(v_price,'.',v_decimal);
    v_line:='';
    for v_field in select value from jsonb_array_elements_text(v_profile->'order') loop
      if v_line<>'' then v_line:=v_line||v_sep; end if;
      v_line:=v_line||case v_field when 'code' then v_code when 'quantity' then v_quantity when 'unit' then '1' else v_price end;
    end loop;
    v_text:=v_text||v_line||v_end;
    v_rows:=v_rows||jsonb_build_array(jsonb_build_object('code',v_code,'description',v_group.description,
      'product_id',v_group.product_id,'measure',v_group.measure,'quantity_milli',v_group.quantity::text,
      'total_cents',v_group.total::text,'price4',v_price4::text,
      'difference7',(v_price4*v_group.quantity-v_group.total*100000)::text));
  end loop;
  v_bytes:=convert_to(v_text,v_profile->>'encoding');
  v_body:=v_body||jsonb_build_object('format_version',2,'profile',v_profile,'filters',p_filters,
    'export_request_hash',v_hash,'grouped_rows',v_rows,'created_by',auth.uid(),
    'artifact',jsonb_build_object('name','consumo_'||p_id||'.txt','base64',replace(encode(v_bytes,'base64'),E'\n',''),
      'sha256',encode(sha256(v_bytes),'hex'),'size',octet_length(v_bytes)),
    'events',jsonb_build_array(jsonb_build_object('action','reserved','actor',auth.uid(),'at',now())));
  update public.export_batches set body=v_body where store_id=p_store and id=p_id;
  return v_body;
end $$;

notify pgrst,'reload schema';
commit;
