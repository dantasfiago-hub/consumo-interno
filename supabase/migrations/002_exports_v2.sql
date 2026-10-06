-- Execute após schema.sql (loja nova) ou diretamente na instalação 1.0/1.1 existente.
-- Migração aditiva: preserva os registros, lotes e referências anteriores.
begin;
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
  if jsonb_array_length(p_profile->'order')<>4 or
     (select count(distinct value) from jsonb_array_elements_text(p_profile->'order'))<>4 or
     exists(select 1 from jsonb_array_elements_text(p_profile->'order') where value not in ('code','quantity','unit','unit_price')) then raise exception 'Ordem dos quatro campos inválida'; end if;
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
    if v_group.quantity<=0 or v_group.total<=0 then raise exception 'Quantidade e valor devem ser positivos'; end if;
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
revoke all on function public.create_export_batch_v2(uuid,uuid,jsonb,jsonb,jsonb) from public,anon;
grant execute on function public.create_export_batch_v2(uuid,uuid,jsonb,jsonb,jsonb) to authenticated;

create or replace function public.update_export_batch_v2(p_store uuid,p_id uuid,p_version integer,p_action text,p_reference text,p_event uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_body jsonb; v_next text;
begin
  if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and role='admin') then raise exception 'Somente administradores alteram lotes'; end if;
  if p_event is null or p_action is null or p_action not in ('authorize_save','saved','imported','cancelled') then raise exception 'Ação inválida'; end if;
  if length(trim(coalesce(p_reference,'')))>200 then raise exception 'Referência muito longa'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
  select body into v_body from public.export_batches where store_id=p_store and id=p_id;
  if v_body is null or v_body->>'format_version' is distinct from '2' then raise exception 'Lote antigo: consulte o histórico da versão anterior'; end if;
  if exists(select 1 from jsonb_array_elements(v_body->'events') e where e->>'id'=p_event::text) then
    if not exists(select 1 from jsonb_array_elements(v_body->'events') e where e->>'id'=p_event::text and e->>'action'=p_action and e->>'reference'=trim(coalesce(p_reference,''))) then raise exception 'Identificador de evento reutilizado'; end if;
    return v_body;
  end if;
  if v_body->>'status'='cancelled' then raise exception 'Lote cancelado'; end if;
  if p_action='authorize_save' then
    if v_body->>'status' in ('ready','downloaded','imported') then return v_body; end if;
    v_next:='ready';
  elsif p_action='saved' then
    if v_body->>'status' not in ('ready','downloaded','imported') then raise exception 'Autorize a gravação antes de confirmar'; end if;
    v_next:=case when v_body->>'status'='imported' then 'imported' else 'downloaded' end;
  elsif p_action='imported' then
    if v_body->>'status' not in ('downloaded','imported') or length(trim(coalesce(p_reference,'')))<3 then raise exception 'Confirme o arquivo salvo e informe referência com 3 a 200 caracteres'; end if;
    v_next:='imported';
  else
    if v_body->>'status'<>'prepared' or length(trim(coalesce(p_reference,'')))<3 then raise exception 'Só é possível liberar um lote sem gravação autorizada, com justificativa'; end if;
    v_next:='cancelled';
  end if;
  -- saved pode chegar depois de outra gravação; é um evento seguro e não libera itens.
  if p_action<>'saved' and (p_version is null or (v_body->>'version')::integer<>p_version) then raise exception 'Lote alterado. Sincronize e confira'; end if;
  v_body:=v_body||jsonb_build_object('status',v_next,'version',(v_body->>'version')::integer+1,
    'updated_at',now(),'events',(v_body->'events')||jsonb_build_array(jsonb_build_object(
      'id',p_event,'action',p_action,'actor',auth.uid(),'at',now(),'reference',trim(coalesce(p_reference,'')))));
  update public.export_batches set body=v_body where store_id=p_store and id=p_id;
  if v_next='cancelled' then delete from public.export_items where store_id=p_store and batch_id=p_id; end if;
  return v_body;
end $$;
revoke all on function public.update_export_batch_v2(uuid,uuid,integer,text,text,uuid) from public,anon;
grant execute on function public.update_export_batch_v2(uuid,uuid,integer,text,text,uuid) to authenticated;

-- Clientes anteriores podem consultar seus lotes, mas não alterar lotes v2.
create or replace function public.update_export_batch(p_store uuid,p_id uuid,p_version integer,p_action text,p_reference text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_body jsonb;
begin
  if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and role='admin') then raise exception 'Somente administradores alteram lotes'; end if;
  if p_version is null or p_version<1 or p_action is null or p_action not in ('issued','cancelled') or length(trim(coalesce(p_reference,''))) not between 3 and 200 then raise exception 'Referência ou justificativa inválida'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
  select body into v_body from public.export_batches where store_id=p_store and id=p_id;
  if v_body is null then raise exception 'Lote inexistente'; end if;
  if v_body->>'format_version'='2' then raise exception 'Atualize o aplicativo para alterar este lote'; end if;
  if v_body->>'status'=p_action and v_body->>'reference'=trim(p_reference) then return v_body; end if;
  if v_body->>'status'<>'prepared' or (v_body->>'version')::integer<>p_version then raise exception 'Lote alterado. Sincronize e confira'; end if;
  v_body:=v_body||jsonb_build_object('status',p_action,'version',p_version+1,'reference',trim(p_reference),'updated_at',now(),'updated_by',auth.uid());
  update public.export_batches set body=v_body where store_id=p_store and id=p_id;
  if p_action='cancelled' then delete from public.export_items where store_id=p_store and batch_id=p_id; end if;
  return v_body;
end $$;
commit;
