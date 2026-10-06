# Validação — 1.6.0+8

Executada em 5 de outubro de 2026, Flutter 3.35.7/Dart 3.9.2 em Linux.

- Análise estática sem ocorrências.
- 88 testes Flutter aprovados, incluindo seis casos novos para ativação/credencial perdida/senha/vetor PBKDF2/offline/bloqueio administrativo. Os testes de interface existentes foram adaptados para não pedir responsável/e-mail e gerar códigos em Administração.
- Sete suítes SQL/PGlite aprovadas. A nova suíte 007 verifica acesso negado antes da ativação, códigos inválidos/expirados/reutilizados, limite de aparelho, papel/setor fixos, substituição e revogação sem reativação por código antigo.
- Evidências em `validation/analyze_1_6.log`, `validation/flutter_tests_1_6.log`, `validation/sql_1_6.log`.
- Capturas em `screenshots/` são renderizações dos testes; não representam execução nativa Windows/telefone físico.

Não houve build de APK/EXE, execução física, acesso ao Supabase da loja nem importação no VR. A identidade anônima foi testada com HTTP controlado; configuração/ativação real precisa ser homologada no projeto. PGlite não mede conexões concorrentes reais.

Aplicar 007 após 006, habilitar Anonymous Sign-Ins e recompilar. Documentação histórica preservada. Limitações de troca/recuperação de credencial e proteção local estão em `ALTERACOES_1_6.md` e no guia.
