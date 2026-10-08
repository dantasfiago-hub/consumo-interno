# Consumo Interno — 1.7.4+15

Flutter para Android e Windows. Registro offline em SQLite/Drift, sincronização Supabase/PostgreSQL e exportação individual por setor para o VR Master. Não emite nota fiscal.

Horti Fruti, Cozinha e Padaria veem somente seus produtos e os módulos de lançamento/cancelamento. Administradores gerenciam catálogo, relatórios, exportações, contas, auditoria, backups e pendências.

## Atualização 1.7.4 — tema para todos os setores

O botão Alterar tema no topo do aplicativo permite escolher Claro, Escuro ou Automático em qualquer setor, sem entrar nas configurações administrativas. A preferência fica salva no aparelho e funciona offline. Os setores continuam com os módulos de lançamento/cancelamento; permissões administrativas não foram alteradas. Recompile para aplicar; não exige SQL. Veja [o guia](docs/ALTERACOES_1_7_4.md).

## Atualização 1.7.3 — backups locais semanais

O intervalo automático local agora é de sete dias desde a última cópia bem-sucedida. A próxima cópia é criada quando houver uso/sincronização após esse prazo; o aplicativo fechado não executa backups. Mantém até 14 cópias por vínculo. Backup manual, ativação e saída/troca de setor continuam podendo gerar cópias adicionais. Backups remotos não foram alterados. Não exige SQL; recompile para aplicar. Veja [o guia](docs/ALTERACOES_1_7_3.md).

## Atualização 1.7.2 — frequência de backups locais

Lançamentos, cancelamentos e cadastros deixam de forçar uma cópia completa a cada gravação. O backup automático respeita o intervalo existente de 24 horas, mantendo até 14 cópias locais. As gravações no SQLite continuam imediatas; ativação, saída/troca de setor e backup manual mantêm suas cópias forçadas. Backups antigos não são apagados por esta atualização. Não exige migração SQL. Veja [o guia](docs/ALTERACOES_1_7_2.md).

## Atualização 1.7.1 — soma nos campos do consumo

Quantidade e valor total aceitam adição sem sinal de igual: `10+20+5`. O resultado aparece enquanto se digita. Kg, gramas e UN aceitam parcelas inteiras; valor total aceita até duas casas por parcela, com vírgula ou ponto decimal. Kg e gramas continuam separados, e a soma de gramas não pode exceder 999. Os botões +/− resolvem a expressão antes de alterar 1; expressões incompletas bloqueiam esses botões e a inclusão do item. Somente o resultado numérico é persistido. Não exige migração SQL. Recompile para usar; esta atualização não inclui APK/EXE novos. Veja [o guia](docs/ALTERACOES_1_7_1.md).

## Atualização 1.7 — conexão incorporada, QR e troca de setor

A conexão padrão pode ser incorporada com `--dart-define-from-file=config/connection.local.json`, mantendo os campos editáveis. A administração gera código e QR de ativação para setores ou administradores adicionais. Android lê pela câmera; Windows/Android podem abrir a imagem PNG. O botão Sair ou trocar de setor sincroniza e grava backup antes de retornar à ativação. Um código novo autoriza a troca; pendências bloqueiam a saída e o último administrador permanece protegido.

Aplique 009 após 008. Leia [o guia 1.7](docs/ALTERACOES_1_7.md). Os valores reais da conexão ainda precisam ser configurados. Não foram gerados novos binários nesta alteração.

## Atualização 1.6.2 — várias máquinas por setor

Aplique [008_multiple_sector_devices.sql](supabase/migrations/008_multiple_sector_devices.sql) após 007. Cada novo código ativa uma máquina adicional, sem desconectar as anteriores. Os códigos valem 24 horas e são de uso único. Revogue uma máquina individualmente em Administração → Aparelhos. Produtos e consumos continuam restritos ao setor; sincronização, cancelamentos e exportações usam os dados compartilhados. Consulte [o guia da atualização](docs/ALTERACOES_1_6_2.md).

Também inclui a correção de fotos WebP estáticas. Fonte 1.7.4+15; não foi gerado um novo APK ou EXE nesta alteração. O APK 1.6.1 citado abaixo é da entrega anterior.

## Correção Android 1.6.1

Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.21 e Java 17. SDK 36 e NDK 28.2.13676358 fixados. Guia completo: [Compilar Android](docs/COMPILAR_ANDROID.md). A assinatura real fica fora do GitHub; `android/key.properties.example` serve somente como modelo. GitHub Actions executa os testes e gera APK debug.

## Atualização 1.6 — aparelho por setor, sem e-mail

O administrador ativa cada aparelho com um código de uso restrito ao setor. Depois, os funcionários abrem diretamente Lançar consumo, sem nome, e-mail ou login diário. O setor é fixo; produtos e consumos continuam isolados. O aparelho administrativo usa senha local própria, inclusive offline.

Habilite Anonymous Sign-Ins no Supabase, aplique 007, 008 e 009 após 006 e siga [LEIA_PRIMEIRO.md](LEIA_PRIMEIRO.md). Loja nova pode usar `supabase/setup_sector_devices.sql` para gerar os quatro códigos iniciais. Não é necessário criar contas de funcionários: o Auth cria identidades técnicas automaticamente. Troca de aparelho deve preservar pendências antes de revogar o antigo.

As exportações por setor, controles kg/gramas/UN e confirmações da 1.5 permanecem. Atualização do fonte: 1.7.4+15; APK anterior release 1.6.1+9 compilado e assinatura verificada. Não foi compilado EXE Windows nesta entrega.

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
| `supabase/migrations/007_sector_devices.sql` | Ativação inicial, vínculos fixos e revogação |
| `supabase/migrations/008_multiple_sector_devices.sql` | Várias máquinas por setor com códigos independentes e preservação dos vínculos existentes |
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

Nuvem nova: esquema base e 002 a 009, nessa ordem. Nuvem 1.6.2: somente 009. Nuvem 1.6/1.6.1: 008 e 009. Nuvem 1.5: 007 a 009. Nuvem 1.4.1: 006 a 009. Nuvem 1.4.0: 005 a 009. Não reaplique o esquema base. Configure loja/códigos pelo SQL e ative os aparelhos; Administração gera códigos dos setores. Não é necessário e-mail.

Consulte [arquitetura](docs/ARQUITETURA_MELHORIAS.md), [alterações](docs/ALTERACOES_1_6.md) e [validação](docs/VALIDACAO.md). Capturas são renderizadas pelos testes Flutter com dados fictícios, não fotos de execução em Windows/telefone físico.

