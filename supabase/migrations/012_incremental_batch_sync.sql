-- Incremental synchronization for export batches.
-- Every insert or update receives a monotonically increasing revision.
begin;

alter table public.export_batches
  add column revision bigserial not null;

create index export_batches_sync_revision
  on public.export_batches(store_id, revision);

create or replace function public.set_export_batch_revision()
returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
  new.revision := nextval('public.export_batches_revision_seq');
  return new;
end $$;

drop trigger if exists export_batches_revision on public.export_batches;
create trigger export_batches_revision
before update on public.export_batches
for each row execute function public.set_export_batch_revision();

notify pgrst, 'reload schema';
commit;
