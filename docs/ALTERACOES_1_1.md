# Versão 1.1 — modularização e aparência

## Mudanças

- Código separado por funcionalidade: produtos, consumos, relatórios e configurações.
- Modelos e validações separados das telas; fotos e PDF têm serviços próprios.
- Composição e navegação em `app/`, utilitários/tema em `core/` e SQLite/nuvem em `infrastructure/`.
- Tema claro, escuro e automático, com preferência local persistida. Campos, totais, badges, navegação, diálogos e mensagens usam cores semânticas.
- Seleção de tema em Configurações → Aparência. Em caso de falha de gravação, a interface mantém a preferência anterior e informa o erro.
- `intl: ^0.20.2` permite a resolução de 0.20.3 no Flutter mais recente.
- Scaffold Linux incluído e correção específica para o aviso C++ do plugin de armazenamento seguro.
- Estados vazios podem rolar em janelas baixas, evitando overflow.

O banco continua na versão de esquema 2 e o protocolo de sincronização não mudou. A aparência não é enviada à nuvem nem modifica lançamentos. As fachadas `domain/models.dart` e `services/files.dart` continuam exportando os símbolos anteriores.

## Atualizar

Guarde uma cópia do código que você modificou e exporte um backup no aplicativo antes de atualizar. Extraia o pacote em uma pasta separada. No Ubuntu, execute `flutter pub get` e `flutter run -d linux`. No Windows, use `scripts/build_windows.ps1`.

O novo APK de teste usa outra assinatura de desenvolvimento. Para substituir o APK anterior, exporte o backup antes de desinstalar, instale esta versão e restaure o backup. Consulte `LEIA_PRIMEIRO.md` para os passos completos.

## Verificação

Análise sem ocorrências. Foram verificados 22 casos únicos: a suíte de 21 casos passou e, após o ajuste do seletor para falhas de gravação, os oito testes de aparência/interface passaram, incluindo o novo caso. Capturas claras e escuras estão em `docs/screenshots/`.

Testes de interface renderizam layouts mobile e desktop. Não houve execução em um telefone físico, Windows nativo ou Ubuntu 26.04 neste ambiente. A versão de Flutter usada aqui foi 3.35.7; sua versão 3.47.5 precisa de validação local.
