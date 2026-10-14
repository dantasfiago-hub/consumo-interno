# Consumo Interno 1.7.5+16 — filtro de produtos por setor

Na tela Produtos do administrador, o seletor Setor oferece Todos os setores, Horti Fruti, Cozinha, Padaria e Sem setor. O filtro usa os setores atribuídos a cada produto e se combina com os filtros existentes de busca, unidade, favoritos e inativos. Um produto vinculado à Cozinha e Padaria aparece nos dois filtros. Sem setor lista os produtos que não têm setores atribuídos.

Filtro somente de visualização, com os dados locais: não altera atribuições, não exige internet e não concede acesso administrativo aos aparelhos dos setores. Os funcionários continuam acessando somente lançamento e cancelamento com seus produtos autorizados.

Atualize com git pull origin main, flutter pub get e recompile com a mesma configuração de conexão e chave Android. Não exige migração Supabase. Não foram gerados APK/EXE.

Validação: revisão do filtro combinado, casos de produto compartilhado e sem setor e análise sintática pelo formatador Dart. Não foram executados testes Flutter ou execução nativa Android/Windows nesta alteração.
