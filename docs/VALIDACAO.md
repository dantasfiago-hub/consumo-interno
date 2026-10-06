# Validação — 1.6.1+9

Executada em 6 de outubro de 2026, Flutter 3.47.5/Dart 3.13.4 em Linux.

- `flutter analyze --no-pub`: nenhuma ocorrência.
- `flutter test --no-pub`: 88 testes aprovados. O menu lateral foi corrigido para atender às verificações de Material do Flutter atual.
- `npm test` em tests_backend: sete suítes SQL/PGlite aprovadas.
- Quatro testes de renderização de interfaces aprovados; capturas claras/escuras atualizadas em screenshots/.
- Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.21, JDK 17, API 36 e NDK 28.2.13676358.
- Evidências: validation/analyze_1_6_1.log, validation/flutter_tests_1_6_1.log e validation/sql_1_6_1.log.

O workflow build.yml foi atualizado e sua estrutura YAML foi verificada. A execução dos jobs no GitHub depende da publicação e ainda não foi validada. Windows requer compilação no Windows.

Não houve execução em aparelho físico, teste com Supabase da loja ou importação real no VR. As capturas são renderizações de testes. PGlite não mede concorrência de conexões reais. A ativação anônima permanece coberta por HTTP controlado e testes SQL; requer homologação no projeto real.

007 continua sendo a última migração. Esta correção não aplica SQL ao projeto Supabase e não altera regras de consumo/exportação/setor.

## Compilação Android

`flutter build apk --release --no-pub` concluído com código de saída 0. Não foi usado o bypass de validação. APK universal 1.6.1+9: compile/target API 36, mínimo Android API 24. `apksigner verify --verbose` aprovado (assinatura v2, um assinante). A chave privada existente foi usada apenas no ambiente local e não integra o ZIP/GitHub.

Os avisos do Flutter sobre remoção futura de suporte a Gradle/AGP/Kotlin não bloquearam esta compilação. O ambiente de teste precisou de JDK completo com javac, SDKs 34/35/36 e configuração de rede; esses arquivos temporários não integram o projeto.
