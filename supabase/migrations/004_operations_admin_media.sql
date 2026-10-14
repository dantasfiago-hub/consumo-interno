-- Execute após 003_sector_access.sql. Migração 1.4 incremental.
begin;
alter table public.memberships add column if not exists features_version integer not null default 4;
create table if not exists public.audit_log (
 id bigserial primary key,store_id uuid not null references public.stores(id),source_key text not null unique,
 actor uuid,device_id uuid,sector text,entity_id uuid,action text not null,detail jsonb not null default '{}',occurred_at timestamptz not null default now());
create index if not exists audit_store_date on public.audit_log(store_id,occurred_at desc,id desc);
alter table public.audit_log enable row level security;
revoke all on public.audit_log from public,anon,authenticated;grant select on public.audit_log to authenticated;
create policy admin_audit on public.audit_log for select to authenticated using(exists(select 1 from public.memberships m where m.store_id=audit_log.store_id and m.user_id=auth.uid() and m.role='admin'));
create or replace function public.audit_operation() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 insert into public.audit_log(store_id,source_key,actor,device_id,sector,entity_id,action,detail)
 values(new.store_id,'operation:'||new.store_id||':'||new.id,new.actor,new.device_id,
 (select sector_id from public.entities where store_id=new.store_id and kind='consumption' and id=new.entity_id),new.entity_id,
 case when new.kind='product' then case when new.expected_version=0 then 'product_created' else 'product_updated' end when new.kind='consumption' then case when new.expected_version=0 then 'consumption_created' else 'consumption_cancelled' end else new.kind end,
 jsonb_build_object('expected_version',new.expected_version,'request_hash',new.request_hash,'reason',(select body->>'cancellation_reason' from public.entities where store_id=new.store_id and id=new.entity_id and kind='consumption'))) on conflict(source_key) do nothing;return new;
end $$;
create trigger operations_audit after insert on public.operations for each row execute function public.audit_operation();
insert into public.audit_log(store_id,source_key,actor,device_id,entity_id,action,detail)
 select store_id,'operation:'||store_id||':'||id,actor,device_id,entity_id,'historical_'||kind,jsonb_build_object('expected_version',expected_version) from public.operations on conflict(source_key) do nothing;
-- Changes to a batch are recorded even for legacy RPCs.
create or replace function public.audit_export() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if tg_op='INSERT' or old.body->>'status' is distinct from new.body->>'status' or old.body->>'version' is distinct from new.body->>'version' then
 insert into public.audit_log(store_id,source_key,actor,sector,entity_id,action,detail)
 values(new.store_id,'batch:'||new.store_id||':'||new.id||':'||(new.body->>'version'),auth.uid(),new.body->>'sector',new.id,'export_'||coalesce(new.body->>'status','reserved'),jsonb_build_object('version',new.body->>'version','file_sha256',new.body->'artifact'->>'sha256')) on conflict(source_key) do nothing;
 end if;return new;
end $$;
create trigger exports_audit after insert or update on public.export_batches for each row execute function public.audit_export();

create or replace function public.admin_members(p_store uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and role='admin')then raise exception 'Acesso administrativo obrigatório';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'email',u.email,'role',m.role,'sector',m.sector) order by u.email) from public.memberships m join auth.users u on u.id=m.user_id where m.store_id=p_store),'[]'::jsonb);
end $$;
create or replace function public.admin_set_member(p_store uuid,p_user uuid,p_role text,p_sector text,p_active boolean) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare before_role text;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
 if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and role='admin')then raise exception 'Acesso administrativo obrigatório';end if;
 if not exists(select 1 from auth.users where id=p_user)then raise exception 'Crie a conta em Authentication antes de vinculá-la';end if;
 if p_active is null then raise exception 'Informe se o acesso está ativo';end if;
 if p_active and (p_role is null or p_role not in('admin','operator') or p_role='operator' and (p_sector is null or p_sector not in('hortifruti','cozinha','padaria')))then raise exception 'Informe papel e setor válidos';end if;
 select role into before_role from public.memberships where store_id=p_store and user_id=p_user;
 if before_role='admin' and (not p_active or p_role<>'admin') and (select count(*) from public.memberships where store_id=p_store and role='admin')<=1 then raise exception 'A loja precisa manter um administrador';end if;
 if p_active then insert into public.memberships(store_id,user_id,role,sector)values(p_store,p_user,p_role,case when p_role='operator' then p_sector end) on conflict(store_id,user_id)do update set role=excluded.role,sector=excluded.sector,features_version=4;
 else delete from public.memberships where store_id=p_store and user_id=p_user;end if;
 insert into public.audit_log(store_id,source_key,actor,entity_id,sector,action,detail)values(p_store,gen_random_uuid()::text,auth.uid(),p_user,p_sector,'membership_changed',jsonb_build_object('previous_role',before_role,'role',p_role,'active',p_active));
end $$;

create table public.sync_issues(store_id uuid not null references public.stores(id),operation_id uuid not null,actor uuid not null,device_id uuid not null,sector text,kind text not null,entity_id uuid not null,expected_version integer not null,snapshot jsonb not null,error text not null,status text not null default 'pending' check(status in('pending','retry','accept_remote','applied')),reviewer uuid,review_reason text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),primary key(store_id,operation_id));
alter table public.sync_issues enable row level security;revoke all on public.sync_issues from public,anon,authenticated;grant select on public.sync_issues to authenticated;
create policy scoped_issues on public.sync_issues for select to authenticated using(exists(select 1 from public.memberships m where m.store_id=sync_issues.store_id and m.user_id=auth.uid() and (m.role='admin' or sync_issues.actor=auth.uid() and m.sector=sync_issues.sector)));
create or replace function public.report_sync_issue(p_store uuid,p_operation uuid,p_device uuid,p_kind text,p_entity uuid,p_expected integer,p_body jsonb,p_error text)returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare member public.memberships;v_sector text;
begin
 select * into member from public.memberships where store_id=p_store and user_id=auth.uid();v_sector:=public.sector_key(p_body->>'sector');
 if p_expected>0 then v_sector:=(select sector_id from public.entities where store_id=p_store and id=p_entity and kind=p_kind);end if;
 if member.user_id is null or p_kind not in('product','consumption') or (p_body->>'id')::uuid<>p_entity or octet_length(p_body::text)>400000 or member.role<>'admin' and (p_kind<>'consumption' or member.sector is null or v_sector is distinct from member.sector)then raise exception 'Pendência fora do acesso autorizado';end if;
 insert into public.sync_issues(store_id,operation_id,actor,device_id,sector,kind,entity_id,expected_version,snapshot,error)values(p_store,p_operation,auth.uid(),p_device,v_sector,p_kind,p_entity,p_expected,p_body-array['photo','_owner','_sector_id','_export_locked'],left(p_error,1000)) on conflict(store_id,operation_id)do update set error=excluded.error,updated_at=now() where sync_issues.actor=auth.uid() and sync_issues.status in('pending','retry');
end $$;
create or replace function public.admin_review_issue(p_store uuid,p_operation uuid,p_action text,p_reason text)returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare issue public.sync_issues;v_body jsonb;v_version integer;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_store::text,0));
 if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and role='admin')then raise exception 'Acesso administrativo obrigatório';end if;
 if p_action not in('retry','accept_remote','apply_local') or length(trim(coalesce(p_reason,''))) not between 3 and 300 then raise exception 'Informe decisão e justificativa';end if;
 select * into issue from public.sync_issues where store_id=p_store and operation_id=p_operation for update;
 if not found then raise exception 'Pendência inexistente';end if;
 if issue.status in('accept_remote','applied')then return;end if;
 if p_action='apply_local' then
 select body,version into v_body,v_version from public.entities where store_id=p_store and kind=issue.kind and id=issue.entity_id for update;
 if issue.kind='product' then raise exception 'Corrija o produto no catálogo e escolha a versão da nuvem';end if;
 if v_body is null then perform public.apply_operation(p_store,issue.operation_id,issue.device_id,issue.kind,0,issue.snapshot||jsonb_build_object('version',1));
 elsif issue.snapshot->>'status'='cancelled' and v_body->>'status'='confirmed' then perform public.apply_operation(p_store,issue.operation_id,issue.device_id,issue.kind,v_version,v_body||jsonb_build_object('version',v_version+1,'status','cancelled','cancellation_reason',issue.snapshot->>'cancellation_reason','cancelled_at',issue.snapshot->>'cancelled_at'));
 else raise exception 'Não é possível sobrescrever dados históricos; escolha a versão da nuvem';end if;
 end if;
 update public.sync_issues set status=case when p_action='apply_local' then 'applied' else p_action end,reviewer=auth.uid(),review_reason=trim(p_reason),updated_at=now() where store_id=p_store and operation_id=p_operation;
 insert into public.audit_log(store_id,source_key,actor,device_id,sector,entity_id,action,detail)values(p_store,gen_random_uuid()::text,auth.uid(),issue.device_id,issue.sector,issue.entity_id,'issue_reviewed',jsonb_build_object('operation_id',p_operation,'decision',p_action,'reason',p_reason,'original_actor',issue.actor));
end $$;

create table public.product_images(store_id uuid not null references public.stores(id),hash text not null check(hash~'^[0-9a-f]{64}$'),data_base64 text not null check(length(data_base64)<=180000),created_by uuid,created_at timestamptz not null default now(),primary key(store_id,hash));
alter table public.product_images enable row level security;revoke all on public.product_images from public,anon,authenticated;grant select on public.product_images to authenticated;
create policy sector_images on public.product_images for select to authenticated using(exists(select 1 from public.entities e where e.store_id=product_images.store_id and e.kind='product' and e.body->>'photo_hash'=product_images.hash));
-- Reuse byte hashes. Existing photos are migrated without changing versions or historical operation hashes.
insert into public.product_images(store_id,hash,data_base64,created_by)select store_id,encode(sha256(decode(body->>'photo','base64')),'hex'),body->>'photo',created_by from public.entities where kind='product' and body->>'photo' is not null on conflict do nothing;
update public.entities set body=(body-'photo')||jsonb_build_object('photo',null,'photo_hash',encode(sha256(decode(body->>'photo','base64')),'hex')),revision=nextval('public.entities_revision_seq')where kind='product' and body->>'photo' is not null;
create or replace function public.upload_product_image(p_store uuid,p_product uuid,p_hash text,p_data text)returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and role='admin')then raise exception 'Acesso administrativo obrigatório';end if;
 if length(p_data)>180000 or encode(sha256(decode(p_data,'base64')),'hex') is distinct from p_hash or not exists(select 1 from public.entities where store_id=p_store and kind='product' and id=p_product and body->>'photo_hash'=p_hash)then raise exception 'Imagem inválida ou produto alterado';end if;
 insert into public.product_images(store_id,hash,data_base64,created_by)values(p_store,p_hash,p_data,auth.uid())on conflict do nothing;
end $$;
create table public.device_backups(store_id uuid not null references public.stores(id),actor uuid not null,device_id uuid not null,scope_role text not null,sector text,hash text not null,payload text not null,created_at timestamptz not null default clock_timestamp(),revision bigserial not null,primary key(store_id,actor,device_id,hash));
alter table public.device_backups enable row level security;revoke all on public.device_backups from public,anon,authenticated;grant select on public.device_backups to authenticated;
create policy device_backups_scoped on public.device_backups for select to authenticated using(exists(select 1 from public.memberships m where m.store_id=device_backups.store_id and m.user_id=auth.uid()and(m.role='admin' or device_backups.actor=auth.uid() and device_backups.scope_role='operator' and device_backups.sector=m.sector)));
create or replace function public.upload_device_backup(p_store uuid,p_device uuid,p_hash text,p_payload text)returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.memberships where store_id=p_store and user_id=auth.uid() and (role='admin' or sector is not null))then raise exception 'Conta não autorizada';end if;
 if length(p_payload)>28000000 or encode(sha256(decode(p_payload,'base64')),'hex')is distinct from p_hash then raise exception 'Backup inválido ou acima de 20 MB comprimidos';end if;
 insert into public.device_backups(store_id,actor,device_id,scope_role,sector,hash,payload)values(p_store,auth.uid(),p_device,(select role from public.memberships where store_id=p_store and user_id=auth.uid()),(select sector from public.memberships where store_id=p_store and user_id=auth.uid()),p_hash,p_payload)on conflict do nothing;
 delete from public.device_backups where store_id=p_store and actor=auth.uid()and device_id=p_device and hash in(select hash from public.device_backups where store_id=p_store and actor=auth.uid()and device_id=p_device order by revision desc offset 7);
end $$;
revoke all on function public.admin_members(uuid),public.admin_set_member(uuid,uuid,text,text,boolean),public.report_sync_issue(uuid,uuid,uuid,text,uuid,integer,jsonb,text),public.admin_review_issue(uuid,uuid,text,text),public.upload_product_image(uuid,uuid,text,text),public.upload_device_backup(uuid,uuid,text,text) from public,anon;
grant execute on function public.admin_members(uuid),public.admin_set_member(uuid,uuid,text,text,boolean),public.report_sync_issue(uuid,uuid,uuid,text,uuid,integer,jsonb,text),public.admin_review_issue(uuid,uuid,text,text),public.upload_product_image(uuid,uuid,text,text),public.upload_device_backup(uuid,uuid,text,text) to authenticated;
notify pgrst,'reload schema';commit;
