import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { randomUUID, createHash } from 'node:crypto';

const db = new PGlite();
await db.exec(`create role anon; create role authenticated; create schema auth;
create table auth.users(id uuid primary key,email text);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema auth to authenticated;grant execute on function auth.uid()to authenticated;`);
for (const file of ['schema.sql','migrations/002_exports_v2.sql','migrations/003_sector_access.sql']) {
  await db.exec(fs.readFileSync(new URL('../supabase/'+file,import.meta.url),'utf8'));
}
const store=randomUUID(), actor=randomUUID(), device=randomUUID(), op=randomUUID();
await db.query('insert into auth.users values($1,$2)',[actor,'admin@loja.test']);
await db.query('insert into stores values($1,$2)',[store,'Loja anterior']);
await db.query("insert into memberships(store_id,user_id,role) values($1,$2,'admin')",[store,actor]);
await db.exec(`set role authenticated;set request.jwt.claim.sub='${actor}'`);
const photo=Buffer.from('foto da versão anterior').toString('base64');
const product={id:randomUUID(),code:'0001',description:'Produto antigo',unit:'UN',photo,active:true,version:1,sectors:['padaria']};
const apply=(kind,operation,body,expected=0)=>db.query('select apply_operation($1,$2,$3,$4,$5,$6::jsonb) result',[store,operation,device,kind,expected,JSON.stringify(body)]);
await apply('product',op,product);
await db.exec('reset role');
await db.exec(fs.readFileSync(new URL('../supabase/migrations/004_operations_admin_media.sql',import.meta.url),'utf8'));
await db.exec(`set role authenticated;set request.jwt.claim.sub='${actor}'`);
const hash=createHash('sha256').update(Buffer.from(photo,'base64')).digest('hex');
const migrated=(await db.query('select body from entities where id=$1',[product.id])).rows[0].body;
assert.equal(migrated.photo,null);assert.equal(migrated.photo_hash,hash);assert.equal(migrated.version,1);
assert.equal((await db.query('select data_base64 from product_images where hash=$1',[hash])).rows[0].data_base64,photo);
assert.equal((await db.query('select features_version from memberships')).rows[0].features_version,4);
assert.equal((await apply('product',op,product)).rows[0].result.duplicate,true);
assert.equal((await db.query('select count(*)::int n from audit_log where actor=$1',[actor])).rows[0].n,1);

const item={id:randomUUID(),product_id:product.id,code:product.code,description:product.description,unit:'UN',amount:3000,total_cents:15357};
const consumption={id:randomUUID(),date:'2026-10-04',created_at:'2026-10-04T10:00:00Z',operator:'Operador',sector:'padaria',note:'',status:'confirmed',version:1,cancellation_reason:null,items:[item]};
await apply('consumption',randomUUID(),consumption);
const profile={version:1,separator:';',decimal:',',encoding:'UTF8',line_ending:'CRLF',header:false,bom:false,fixed_price:false,validated:true,order:['code','quantity','unit','unit_price']};
const requests=[{consumption_id:consumption.id,item_id:item.id,version:1}];
const reserve=()=>db.query('select create_export_batch_v3($1,$2,$3::jsonb,$4::jsonb,$5::jsonb,$6) result',[store,randomUUID(),JSON.stringify(requests),JSON.stringify(profile),JSON.stringify({sector:'padaria'}),'padaria']);
// PGlite serializes commands. This verifies overlapping requests and SQL reservation
// invariants; it is not a benchmark of separate production PostgreSQL connections.
const attempts=await Promise.allSettled([reserve(),reserve()]);
assert.equal(attempts.filter(a=>a.status==='fulfilled').length,1);
await db.exec('reset role');
const active=(await db.query("select count(*)::int n from export_items i join export_batches b on b.store_id=i.store_id and b.id=i.batch_id where i.consumption_id=$1 and b.body->>'status'<>'cancelled'",[consumption.id])).rows[0].n;
assert.equal(active,1);
console.log('PASS: atualização de loja existente preserva fotos, versões e idempotência; auditoria retroativa; duas requisições de exportação não reservam o mesmo item');
await db.close();
