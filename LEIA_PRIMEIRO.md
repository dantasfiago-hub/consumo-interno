# Consumo Interno 1.7.6+17 — instalação e atualização

Este guia explica **como instalar e atualizar**. O que mudou em cada versão está em [CHANGELOG.md](CHANGELOG.md); os detalhes por versão estão em `docs/`.

## Migrações do Supabase

Execute no SQL Editor, na ordem. Não reaplique `schema.sql` nem `setup_sector_devices.sql` em uma loja existente.

| Migração | Para que serve |
| --- | --- |
| `schema.sql` | Estrutura inicial (somente loja nova) |
| 002 a 006 | Exportações v2, acesso por setor, operações/mídia, correções de revisão, exportação por setor |
| 007 a 009 | Aparelhos por setor, várias máquinas por setor, ativação e troca de setor |
| 010 `backup_retention` | Retenção de duas cópias remotas por aparelho (remove as excedentes) |
| 011 `admin_device_listing` | Metadados para a lista administrativa de aparelhos ([guia](docs/GESTAO_APARELHOS.md)) |
| 012 `incremental_batch_sync` | Coluna `revision` em `export_batches`; o aplicativo atual a lê. Idempotente: em loja nova o `schema.sql` já a contém e a 012 não altera nada |

### Supabase existente
Execute somente as migrações posteriores à última que já aplicou, em ordem. Exemplo: se a última foi a 009, execute 010, 011 e 012. Se foi a 007, execute de 008 a 012.

### Supabase novo
1. Crie o projeto e habilite Authentication → Allow anonymous sign-ins.
2. Execute `schema.sql` e todas as migrações 002 a 012, nessa ordem.
3. Execute uma única vez `setup_sector_devices.sql`, alterando o nome da loja. Guarde o UUID e os códigos iniciais de uso único, válidos por 24 horas.
4. Ative o aparelho administrativo. Sem configuração incorporada, preencha URL HTTPS, chave pública e UUID da loja, junto com o código administrativo. Defina a senha local.
5. Na administração, gere códigos/QRs para os demais aparelhos. Cada aparelho tem um código próprio; pode haver várias máquinas por setor e vários administradores.

Não é necessário criar funcionários ou e-mails. O Supabase cria identidades técnicas anônimas; não as apague enquanto os aparelhos dependerem delas. Não use `service_role` nem `sb_secret_` no aplicativo. Recomenda-se ativar CAPTCHA ou limite de taxa para logins anônimos no Supabase.

## Atualizar e compilar

```text
git pull origin main
flutter pub get
flutter analyze
flutter test
```

Para deixar a conexão incorporada, configure `config/connection.local.json` e use `--dart-define-from-file=config/connection.local.json` ao compilar. O modelo está em `config/connection.example.json`. Android release exige o kit de assinatura privado existente ([guia](docs/COMPILAR_ANDROID.md)); Windows exige Flutter e Visual Studio C++ no Windows. A pasta `supabase` pode permanecer no projeto; os SQL precisam ser executados separadamente na nuvem. Recompile todos os aparelhos depois de atualizar: os binários anteriores não incluem as alterações novas.

Os testes de backend (`tests_backend`, `npm ci && npm test`) aplicam `schema.sql` e todas as migrações em ordem num PostgreSQL em memória.

## Como o aplicativo é operado

- Os setores acessam apenas lançamento/cancelamento e seus produtos.
- A exportação administrativa reúne registros sincronizados por setor, ignorando os já reservados/exportados. Cozinha e Padaria exportam código e quantidade; Horti Fruti mantém os quatro campos. Sincronize todas as máquinas antes de exportar.
- Para trocar de setor ou de loja, use **Sair ou trocar de setor** e um novo código autorizado. A saída exige sincronização concluída e backup local. Os dados antigos permanecem na nuvem e na cópia local; rascunhos ainda não lançados são descartados com confirmação. Não apague banco ou credenciais para contornar pendências.
- Backups: até quatro cópias locais por vínculo (intervalo automático semanal) e duas na nuvem por aparelho; a nuvem é verificada no máximo a cada 30 minutos após sincronizar.

## Estado da validação

Esta revisão não aplicou SQL à loja nem compilou novos APK/EXE. As limitações de validação das versões anteriores estão registradas em [docs/ALTERACOES_1_7.md](docs/ALTERACOES_1_7.md).
