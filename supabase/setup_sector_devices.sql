-- SOMENTE LOJA NOVA: execute uma vez no SQL Editor depois de schema + 002 a 007.
-- Altere o nome. Guarde o UUID e os códigos retornados (validade: 24 horas).
-- Não exige criar contas em Authentication: cada aparelho cria sua identidade técnica.
begin;
with loja as (
  insert into public.stores(name) values ('Meu supermercado') returning id
)
select id as uuid_da_loja,
  public.provision_sector_device(id,'admin') as aparelho_administrativo,
  public.provision_sector_device(id,'hortifruti') as hortifruti,
  public.provision_sector_device(id,'cozinha') as cozinha,
  public.provision_sector_device(id,'padaria') as padaria
from loja;
commit;
