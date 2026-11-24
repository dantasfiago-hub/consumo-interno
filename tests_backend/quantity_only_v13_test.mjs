import {PGlite} from '@electric-sql/pglite';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const root=new URL('../supabase/',import.meta.url);
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
await db.exec(fs.readFileSync(new URL('schema.sql',root),'utf8'));
const migrations=fs.readdirSync(new URL('migrations/',root)).filter(f=>/^\d{3}_.*\.sql$/.test(f)).sort();
assert.ok(migrations.includes('013_quantity_only_sectors.sql'));
const upTo=n=>migrations.filter(f=>f<=n);
// Loja existente: 002..012 já aplicadas, depois a 013.
for(const f of upTo('012_incremental_batch_sync.sql')) await db.exec(fs.readFileSync(new URL('migrations/'+f,root),'utf8'));
const store=randomUUID(),admin=randomUUID(),device=randomUUID();
await db.query('insert into auth.users values($1,$2)',[admin,'admin@test']);
await db.query('insert into stores values($1,$2)',[store,'Loja']);
await db.query("insert into memberships(store_id,user_id,role,sector) values($1,$2,'admin',null)",[store,admin]);
await db.exec(`set role authenticated;set request.jwt.claim.sub='${admin}'`);
const apply=(kind,body)=>db.query('select apply_operation($1,$2,$3,$4,0,$5::jsonb)',[store,randomUUID(),device,kind,JSON.stringify(body)]);
const product={id:randomUUID(),code:'000125',description:'Produto',unit:'UN',active:true,version:1,sectors:['cozinha','padaria','hortifruti'],photo:null};
await apply('product',product);
const make=(sector,total)=>({id:randomUUID(),date:'2026-10-05',created_at:'2026-10-05T12:00:00Z',operator:sector,sector,note:'',status:'confirmed',version:1,
  items:[{id:randomUUID(),product_id:product.id,code:product.code,description:product.description,unit:'UN',amount:3000,total_cents:total}]});
// Antes da 013: total 0 é recusado em qualquer setor.
await assert.rejects(()=>apply('consumption',make('cozinha',0)),/Quantidade ou valor inválido/);
await db.exec('reset role');
await db.exec(fs.readFileSync(new URL('migrations/013_quantity_only_sectors.sql',root),'utf8'));
await db.exec(fs.readFileSync(new URL('migrations/013_quantity_only_sectors.sql',root),'utf8')); // idempotente
await db.exec(`set role authenticated;set request.jwt.claim.sub='${admin}'`);
// Depois da 013: Cozinha e Padaria aceitam 0; Horti Fruti continua exigindo valor.
const kitchen=make('cozinha',0),bakery=make('padaria',0),priced=make('cozinha',250);
await apply('consumption',kitchen);await apply('consumption',bakery);await apply('consumption',priced);
await assert.rejects(()=>apply('consumption',make('hortifruti',0)),/Quantidade ou valor inválido/);
await apply('consumption',make('hortifruti',250));
await assert.rejects(()=>apply('consumption',make('padaria',-1)));
// Exportação: Cozinha com itens de total 0 e com valor, só código e quantidade.
const profile={version:1,separator:';',decimal:',',encoding:'UTF8',line_ending:'CRLF',header:false,bom:false,fixed_price:false,validated:true,order:['code','quantity','unit','unit_price']};
const item=c=>({consumption_id:c.id,item_id:c.items[0].id,version:c.version});
const batch=(sector,cs,p=profile)=>db.query('select create_export_batch_v3($1,$2,$3::jsonb,$4::jsonb,$5::jsonb,$6) body',[store,randomUUID(),JSON.stringify(cs.map(item)),JSON.stringify(p),'{}',sector]);
const text=b=>Buffer.from(b.artifact.base64,'base64').toString('utf8');
const k=(await batch('cozinha',[kitchen,priced])).rows[0].body;
assert.equal(text(k),'000125;6\r\n');
const b=(await batch('padaria',[bakery])).rows[0].body;
assert.equal(text(b),'000125;3\r\n');
console.log('PASS: migração 013 — total 0 aceito só em Cozinha/Padaria, Horti Fruti exige valor, exportação por quantidade com itens sem valor, migração idempotente');
