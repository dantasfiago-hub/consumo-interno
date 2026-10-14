# Correções Android — 1.6.1+9

- Gradle 8.12 → 8.14.3; atende ao mínimo 8.14 indicado pelo Flutter 3.47.5 do usuário. SHA-256 oficial da distribuição incluído no wrapper.
- AGP 8.9.1 → 8.11.1 e Kotlin 2.1.0 → 2.2.21; alinhados à matriz de compatibilidade das ferramentas.
- API 36 e NDK 28.2.13676358 explicitamente fixados. JDK 17 permanece exigido pelo AGP.
- Wrapper/scripts passam a poder ser versionados. Gradlew tem permissão de execução.
- Modelo de assinatura sem segredos e instruções para SDK via terminal.
- Workflow GitHub testa o código/SQL e compila APK debug sem usar a chave privada.
- Menu lateral usa Material para renderizar seleção e ink corretamente; corrige as exceções detectadas nos testes com Flutter 3.47.5.
- Lock atualizado para as dependências do Flutter 3.47.5, incluindo intl 0.20.3.
- Versão do aplicativo/instalador alterada para 1.6.1+9. Nenhuma migração SQL nova: 007 continua a mais recente.

Essas alterações tratam configuração/build e o fundo do menu lateral. Não alteram consumo, exportação VR ou autenticação por setor. Validação e limitações atualizadas em VALIDACAO.md.
