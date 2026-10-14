# Logout e consultas de histórico

- O logout legado remove tanto o refresh token antigo quanto o token por
  conexão/loja, limpa a identidade em memória e invalida o acesso local. Mantém
  vínculo, registros e fila pendente. Aparelhos ativados continuam usando o fluxo
  existente de saída/troca de setor, que sincroniza e preserva backup.
- A recarga geral do aplicativo mantém somente os 50 consumos mais recentes.
  O histórico consulta registros em ordem estável no SQLite e permite carregar
  mais em blocos de 50. A busca explícita consulta todo o histórico autorizado,
  inclusive registros antigos; os resultados visíveis continuam paginados.
- Relatórios consultam o conjunto completo ao aplicar filtros ou pedir o
  histórico completo. Exportações consultam o conjunto completo do setor
  selecionado, incluindo consumos anteriores à primeira página. A conferência
  após sincronização também consulta o banco completo antes da reserva.
- Telas de relatório/exportação fora da aba ativa não disparam consultas
  completas. Alterações locais e sincronizações invalidam os resultados visíveis.
  Campos preenchidos permanecem na tela durante o carregamento.
- Consultas de consumo usam parâmetros tipados; o filtro de acesso por setor e
  a ordenação ocorrem no SQLite. O formato JSON de registros e backups permanece
  compatível com os dados existentes.
- O SQLite migra automaticamente da versão 2 para a 3, acrescentando um índice
  para ordenar o histórico. Não requer migração adicional no Supabase.
- `config/connection.json` passa a ser ignorado pelo Git, assim como o nome
  recomendado `config/connection.local.json`. Veja `config/README.md`.

Recompile o aplicativo para aplicar. Não foram gerados APK/EXE nesta alteração.

## Validação

Validado com Flutter 3.47.5 / Dart 3.13.4:

- `flutter analyze --no-pub`: sem problemas.
- `flutter test --no-pub --reporter expanded`: 120 testes aprovados.
- `npm test` em `tests_backend`: 11 suítes aprovadas.
- `git diff --check`: aprovado.

As regressões novas verificam remoção dos dois formatos de token sem perda de
pendências, proteção da credencial dos aparelhos, ordem estável e isolamento por
setor nas páginas, migração de instalação v2 e busca/relatório/exportação com
registros além da primeira página. Os testes de interface existentes verificam
preservação dos filtros nas telas de 390 e 1280 pixels, nos temas claro e escuro.
