# Arquitetura implementada — Consumo Interno 1.4

Flutter atende Android/Windows; SQLite/Drift mantém registros e fila offline. Supabase Authentication identifica a conta; PostgreSQL/RPC/RLS verifica permissões e protege operações entre dispositivos. O aplicativo prepara dados para o VR Master; não emite documentos fiscais.

## Composição e responsabilidades

`AppState` é a fachada observável utilizada pelas telas. Não concentra as regras de catálogo, cancelamento ou sessão: delega para controladores e compõe suas listas/status. A evolução manteve as APIs públicas usadas pelas telas existentes.

| Componente | Responsabilidade |
|---|---|
| `SessionController` | Vínculo, papel, setor e acesso previamente validado |
| `CatalogController` | Carga autorizada, ordenação e gravação administrativa |
| `ConsumptionController` | Produtos permitidos, histórico e cancelamento com proteção de exportação |
| `SynchronizationController` | Uma operação de nuvem por vez, timer, retentativas, estado e descarte do timer |
| `BackupController` | Snapshot consistente, namespace por vínculo, checksum, rename atômico e retenção |
| `AdministrationController` | Vínculos, pendências, auditoria filtrada/paginada e backups |
| `ExportController` e casos de uso | Perfil, elegibilidade, conferência, reserva, salvamento e recibo persistente |
| `LocalDatabase` | Transações, registros, outbox, staging incremental, imagens e arquivos de conflitos |
| `CloudService` | Sessão segura, chamadas REST/RPC, fotos incrementais, revisão e backups remotos |

Domínio e serialização de exportação não dependem de widgets. A infraestrutura continua compartilhada: esta é uma aplicação modular, sem processos distribuídos separados para cada funcionalidade.

## Dados e precisão

Produto: UUID, código interno textual, descrição, UN/KG, ativo, versão, setores e hash da foto. Consumo: UUID, data/instante, responsável informado, setor autenticado, itens históricos, situação, versão e justificativa. A conta autenticada é distinta do nome digitado em Responsável.

Quantidades usam milésimos; UN é múltiplo de 1000. Valores totais usam centavos. `BigInt` e PostgreSQL `numeric` calculam agrupamentos sem `double`, com arredondamento half-up apenas no resultado. O TXT contém código, quantidade somada, unidade fixa `1` e preço unitário em até quatro casas. Divergências de reconstrução por arredondamento ficam visíveis na conferência.

A identidade do item é lançamento/item, não código/data. Cada exportação seleciona um único setor. A reserva valida versões e disponibilidade sob bloqueio transacional da loja; itens de outros lotes ativos são ignorados. O lote guarda seleção, perfil, filtros, arquivo, tamanho, hash e eventos. Cancelar reserva só libera antes da autorização de salvamento. Depois, downloads usam o mesmo artefato.

## Sincronização e revisão

Registro e outbox são atômicos. O UUID da operação e o corpo original ficam estáveis para reenvio idempotente; versão esperada detecta conflito. Páginas recebidas são preparadas no staging e aplicadas junto com o cursor numa transação. Permissões revogadas são invalidadas quando confirmadas; offline mantém a última autorização e desconhece mudanças em outro dispositivo.

A execução é serializada localmente. Uma falha agenda espera progressiva até 15 minutos; envio manual pode tentar imediatamente. Timer consulta a agenda a cada 15 segundos e sincroniza normalmente a cada minuto, somente enquanto aberto. Ao salvar/retornar ao app também há envio. Não existe serviço contínuo com app encerrado.

Erros permanentes de operações elegíveis são reportados à `sync_issues`; a operação original continua no aparelho. O administrador pode pedir reenvio, manter a versão remota ou aplicar consumo válido. Toda decisão exige motivo. `apply_local` não sobrescreve produtos/histórico nem contorna a proteção de exportação. `accept_remote`/`applied` arquivam conteúdo e operações originais antes de adotar o servidor. Falha ao registrar a pendência central não descarta a fila local.

## Permissões e auditoria

`memberships` define admin ou operator e um setor fixo. Setores possuem somente duas páginas: lançamento e cancelamento. Produtos exigem vínculo com o setor. RLS/RPC aplicam as mesmas restrições no servidor. Reclassificação legada e administração exigem admin. O último admin não pode ser desativado/rebaixado. Credenciais são criadas no Authentication; a tela administra vínculos existentes sem expor service_role.

`audit_log` recebe operações por trigger e eventos de exportação/revisão/vínculo. Inclui ator, dispositivo quando disponível, setor, entidade, ação, instante e detalhes. Registros anteriores são incorporados por migração. Usuários comuns não leem o livro central; admin tem leitura e filtros, sem DELETE/UPDATE direto.

## Imagens e recuperação

Fotos são compactadas no editor, deduplicadas por SHA-256 no SQLite e na tabela `product_images`, separada de `entities`. Metadados referenciam o hash; as páginas buscam somente hashes ainda ausentes e verificam bytes antes de armazenar. RLS limita imagens a produtos autorizados. A migração extrai fotos antigas sem mudar versões/request_hash de operações já gravadas.

`BackupController` grava envelope com SHA-256 via arquivo temporário e rename, mantém 14 últimas cópias por vínculo e registra falhas. Após mutações gera cópia; durante uso cria diariamente mesmo sem mutação. Pasta personalizada é administrativa. Backups no diretório do aplicativo precisam ser copiados para fora antes de desinstalar.

Snapshots remotos são comprimidos e enviados apenas quando o hash muda; `device_backups` mantém 7 por conta/dispositivo. Escopo de conta/setor é verificado pelo servidor. Instalação vazia busca snapshot autorizado da própria conta e sincroniza novamente com cursor zero. JSON manual continua disponível ao administrador. Restaurar preserva UUIDs e permissões atuais, verifica vínculo/checksum e rejeita banco não vazio. Descompressão é limitada a 64 MB e transporte a 20 MB comprimidos; erros não apagam o banco.

## Distribuição e verificação

Versão 1.4.0+5 com ícone Android/Windows e APK release ARM64. A chave de assinatura é entregue em kit privado separado; código/Git excluem as credenciais. Compilar release sem chave falha explicitamente. Próximas versões precisam reutilizar a chave e aumentar o código de versão.

Testes cobrem domínio, persistência, permissão, backups, telas responsivas/temas, HTTP com duas instalações e SQL/RLS/migração de loja existente. PostgreSQL/PGlite serializa comandos; os testes de reserva verificam invariantes e não substituem validação com conexões reais. Veja VALIDACAO.md para resultados e limites. Não houve execução física no Android, execução nativa Windows, alteração da nuvem da loja nem importação real no VR.
