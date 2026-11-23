import {PGlite} from '@electric-sql/pglite';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const root=new URL('../supabase/',import.meta.url);
const db=new PGlite();
await db.exec(`create role anon; create role authenticated; create schema auth; create table auth.users(id uuid primary key); create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$; grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;`);
await db.exec(fs.readFileSync(new URL('schema.sql',root),'utf8'));
const migrations=fs.readdirSync(new URL('migrations/',root)).filter(f=>/^\d{3}_.*\.sql$/.test(f)).sort();
// A new store must accept every migration, in order, after the current schema.sql.
for(const file of migrations) await db.exec(fs.readFileSync(new URL('migrations/'+file,root),'utf8'));
// Existing stores may run the incremental-sync migration again without error.
const incremental=fs.readFileSync(new URL('migrations/012_incremental_batch_sync.sql',root),'utf8');
await db.exec(incremental);
const store='11111111-1111-4111-8111-111111111111',user='22222222-2222-4222-8222-222222222222',batch='33333333-3333-4333-8333-333333333333';
await db.exec(`insert into auth.users values('${user}'); insert into stores values('${store}','Loja'); insert into export_batches(store_id,id,created_by,body) values('${store}','${batch}','${user}','{"version":1,"sector":"cozinha","status":"reserved"}');`);
const first=(await db.query('select revision::int r from export_batches where id=$1',[batch])).rows[0].r;
await db.exec(`update export_batches set body='{"version":2,"sector":"cozinha","status":"reserved"}' where id='${batch}'`);
const second=(await db.query('select revision::int r from export_batches where id=$1',[batch])).rows[0].r;
assert.ok(second>first,'a atualização deve aumentar a revisão do lote');
console.log('instalação nova + migração 012 repetida: ok');
