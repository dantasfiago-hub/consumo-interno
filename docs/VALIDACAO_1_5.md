# Validação — 1.5.0+7

Executada em 5 de outubro de 2026 com Flutter 3.35.7 / Dart 3.9.2 em Linux.

- Análise estática: sem ocorrências.
- 82 testes Flutter aprovados, incluindo seis novos testes desta atualização. O fluxo de lançamento existente verifica voltar/confirmar nos layouts de 390 e 1280 pixels, temas claro e escuro.
- Novos testes verificam peso separado, entradas inválidas, botões/limites, bytes dos dois formatos, cabeçalho/decimal e cancelamento das confirmações de exportação antes de reservar/autorizar.
- Seis suítes PostgreSQL/PGlite aprovadas. A suíte 006 verifica agrupamento, kg com precisão de 1 g, dois campos Cozinha/Padaria, quatro Horti Fruti, RLS, exclusão de itens protegidos e preservação/idempotência de lotes antigos.
- Capturas em `screenshots/` são renderizadas por testes Flutter com dados fictícios; incluem campos de peso e confirmação. Não representam execução nativa em Windows ou Android físico.
- Logs: `validation/analyze_1_5.log`, `validation/flutter_tests_1_5.log`, `validation/sql_1_5.log`.

Nenhum APK/EXE foi compilado nesta atualização. Não houve execução nativa Windows, Android físico, Supabase da loja ou importação real no VR. Nenhuma migração foi aplicada à loja. PGlite não substitui testes de conexões concorrentes reais.

Aplicar 006 após 005 e recompilar. APK anterior 1.4.0+5 não inclui estas alterações; documentação histórica preservada em `VALIDACAO_1_4.md` e `VALIDACAO_1_4_1.md`.
