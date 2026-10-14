# Alterações — 1.4.1+6

Revisão corretiva de gravação, sincronização, restauração, permissões, fotos e auditoria. Relatório completo: [REVISAO_CODIGO_1_4_1.md](REVISAO_CODIGO_1_4_1.md).

- Gravação concluída não é apresentada como falha por um erro posterior; operador gravado atomicamente.
- Fila mantém corpo estável; SQL separa mídia atomicamente e preserva idempotência histórica.
- Restauração exige vínculo e não concede permissões; backup respeita o setor atual.
- Validação de código interno, proteção de exportação, justificativa e data de cancelamento.
- Sincronização recupera de falha de recarga e tenta baixar imagens ausentes novamente.
- Paginação administrativa, processamento de fotos fora da interface, descarte seguro de controladores e recarga do tema restaurado.
- Backups limitados a 20 MiB comprimidos; fotos órfãs fora das cópias; data da auditoria histórica corrigida.
- 76 testes Flutter e cinco suítes SQL aprovados; análise estática sem ocorrências.

Aplicar migração 005 após 004. Não reaplicar o esquema base. Recompilar Android/Windows. O APK 1.4.0+5 anterior não inclui estas correções.
