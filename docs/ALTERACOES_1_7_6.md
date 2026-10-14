# Consumo Interno 1.7.6+17 — retenção de backups

- Local: até quatro cópias automáticas por pasta de vínculo/aparelho. O intervalo continua em sete dias desde a última cópia bem-sucedida, durante o uso do aplicativo. O limite vale também para cópias forçadas feitas na mesma pasta; a exportação manual para um arquivo escolhido pelo administrador não entra nessa rotação.
- Supabase: até duas cópias por loja/identidade/aparelho. Uploads ocorrem após sincronizar quando o conteúdo do backup muda; não são semanais.
- Cópias forçadas de ativação e saída/troca de setor continuam funcionando. Registros continuam sendo gravados imediatamente no SQLite e na fila de sincronização.

## Aplicar

1. Atualize com git pull origin main.
2. No Supabase SQL Editor, execute supabase/migrations/010_backup_retention.sql depois de 009. Não reaplique schema.sql na loja existente.
3. Execute flutter pub get e recompile Android/Windows com a mesma conexão e chave de assinatura.

A migração reduz as cópias remotas existentes imediatamente, mantendo as duas com maior revision por grupo. Não altera produtos, consumos, contas nem permissões. A função upload_device_backup passa a usar retenção dois e serializa uploads do mesmo grupo para evitar excesso por concorrência. Permissões, checagem do hash e limite de tamanho permanecem.

Os arquivos locais excedentes são removidos depois da próxima cópia bem-sucedida. Para aplicar a rotação sem esperar a semana, use Configurações → Backup e recuperação → Criar cópia agora com backup automático habilitado. Os arquivos exportados manualmente para outro local não são apagados.

## Validação

Suíte PostgreSQL/PGlite executada com schema.sql e migrações 002 a 010: preservação das duas versões mais recentes, isolamento de loja/ator/aparelho, uploads sucessivos, repetição da migração/upload e validação/autorização aprovados. A suíte foi adicionada ao npm test. Validação local limitada à revisão da alteração de retenção e sintaxe Dart; testes Flutter e APK/EXE não foram executados/gerados. Nenhum SQL foi aplicado ao Supabase real da loja.
