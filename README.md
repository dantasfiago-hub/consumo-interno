# Consumo Interno — 1.6.1+9

Flutter para Android e Windows. Registro offline em SQLite/Drift, sincronização Supabase/PostgreSQL e exportação individual por setor para o VR Master. Não emite nota fiscal.

Horti Fruti, Cozinha e Padaria veem somente seus produtos e os módulos de lançamento/cancelamento. Administradores gerenciam catálogo, relatórios, exportações, contas, auditoria, backups e pendências.

## Correção Android 1.6.1

Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.21 e Java 17. SDK 36 e NDK 28.2.13676358 fixados. Guia completo: [Compilar Android](docs/COMPILAR_ANDROID.md). A assinatura real fica fora do GitHub; `android/key.properties.example` serve somente como modelo. GitHub Actions executa os testes e gera APK debug.

## Atualização 1.6 — aparelho por setor, sem e-mail

O administrador ativa cada aparelho com um código de uso restrito ao setor. Depois, os funcionários abrem diretamente Lançar consumo, sem nome, e-mail ou login diário. O setor é fixo; produtos e consumos continuam isolados. O aparelho administrativo usa senha local própria, inclusive offline.

Habilite Anonymous Sign-Ins no Supabase, aplique 007 após 006 e siga [LEIA_PRIMEIRO.md](LEIA_PRIMEIRO.md). Loja nova pode usar `supabase/setup_sector_devices.sql` para gerar os quatro códigos iniciais. Não é necessário criar contas de funcionários: o Auth cria identidades técnicas automaticamente. Troca de aparelho deve preservar pendências antes de revogar o antigo.

As exportações por setor, controles kg/gramas/UN e confirmações da 1.5 permanecem. Atualização do fonte: 1.6.1+9; APK release 1.6.1+9 compilado e assinatura verificada. Não foi compilado EXE Windows nesta entrega.

## Implementação

| Área | Responsabilidade |
|---|---|
| `lib/app/controllers` | Sessão, catálogo, consumo e sincronização; `AppState` compõe os controladores |
| `lib/features/administration` | Contas existentes, revisão central de pendências, auditoria e backups remotos |
| `lib/features/backup` | Cópias automáticas locais, retenção e gravação atômica |
| `lib/features/products` | Código, descrição, UN/KG, setores permitidos e fotos |
| `lib/features/consumption` | Lançamentos, histórico e cancelamentos com justificativa |
| `lib/features/reports` | Filtros, detalhamento e PDF/CSV |
| `lib/features/exports` | Perfil, precisão, agrupamentos, reserva, arquivo imutável e conferência por setor |
| `lib/core` | Tema claro/escuro/sistema, acesso, números, arquivos e integridade de backups |
| `lib/infrastructure` | SQLite/Drift e transporte REST/Supabase |
| `supabase/migrations/004_operations_admin_media.sql` | Auditoria, gestão de vínculos, revisão, imagens e backups com RLS |
| `supabase/migrations/005_review_fixes.sql` | Idempotência de mídia, código interno, limites e datas históricas |
| `supabase/migrations/006_sector_export_quantity.sql` | Formato por setor; preservação dos arquivos já gerados |
| `supabase/migrations/007_sector_devices.sql` | Ativação, limite de um aparelho por setor, vínculos fixos e revogação |
| `assets/branding`, `android/.../res`, `windows/runner/resources` | Ícone original na interface e nos binários |

Quantidades são milésimos e valores são centavos. `BigInt` no cliente e `numeric` no servidor calculam o preço depois de somar: `arredondar(total_centavos × 100000 / quantidade_milésimos)`. Para Horti Fruti, o TXT exporta código, quantidade, unidade fixa `1` e preço em até quatro casas. Para Cozinha/Padaria, exporta apenas código e quantidade, nessa ordem. Peso sai em kg (2 kg + 350 g = `2,35` no perfil com vírgula), e UN como número inteiro. Zeros iniciais do código são preservados.

Itens reservados/exportados não podem entrar em outro lote. O arquivo guarda bytes/SHA-256 imutáveis; novo download reutiliza o lote. Reserva exige internet. Importação no VR é conferida e confirmada manualmente.

Fila e registro são gravados na mesma transação. UUIDs tornam reenvios idempotentes; versões detectam conflitos. O recebimento aplica páginas/cursor atomicamente. Revisões administrativas arquivam a tentativa original. Fotos usam SHA-256 e cache separado dos metadados. Permissões são verificadas no servidor e aplicadas também nos controladores locais.

Backups locais mantêm 14 cópias por conta; remotos mantêm 7 por conta/dispositivo. Restauração verifica integridade, vínculo e permissões. Em instalação vazia, há recuperação remota autorizada antes da sincronização.

## Instalação e testes

Leia [LEIA_PRIMEIRO.md](LEIA_PRIMEIRO.md) antes de atualizar: a versão 1.4 muda da antiga assinatura debug para a chave release do kit privado. Sincronize e preserve backups antes de desinstalar.

```powershell
flutter pub get
flutter analyze
flutter test
cd tests_backend
npm ci
npm test
```

O ambiente de validação da 1.6.1 usa Flutter 3.47.5/Dart 3.13.4. O build Android release exige o kit privado de assinatura. O código ZIP exclui suas credenciais; não publique o kit. O Windows precisa ser compilado em Windows com Visual Studio C++.

Nuvem nova: esquema base e 002 a 007, nessa ordem. Nuvem 1.5: somente 007. Nuvem 1.4.1: 006 e 007. Nuvem 1.4.0: 005 a 007. Não reaplique o esquema base. Configure loja/códigos pelo SQL e ative os aparelhos; Administração gera códigos dos setores. Não é necessário e-mail.

Consulte [arquitetura](docs/ARQUITETURA_MELHORIAS.md), [alterações](docs/ALTERACOES_1_6.md) e [validação](docs/VALIDACAO.md). Capturas são renderizadas pelos testes Flutter com dados fictícios, não fotos de execução em Windows/telefone físico.
