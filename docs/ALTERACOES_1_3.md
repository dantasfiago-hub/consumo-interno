# Versão 1.3.0+4 — isolamento de setores

- Contas de Horti Fruti, Cozinha e Padaria, restritas a consumo/cancelamento.
- Catálogo e dados locais filtrados; RLS e operações SQL conferem o setor.
- Produto pode pertencer a mais de um setor, explicitamente; catálogo antigo sem setor fica restrito ao administrador.
- Conta sem vínculo ou sem setor não recebe acesso operacional. Revogação confirmada pela nuvem remove o acesso local; alterações só são conhecidas pelo aparelho ao conectar.
- Cancelamento do próprio setor, inclusive entre funcionários, com justificativa; reserva/exportação impede o cancelamento.
- Exportação administrativa individual por setor e exclusão automática dos itens já reservados/exportados; transação, idempotência e proteção contra concorrência mantidas.
- Classificação administrativa de consumos antigos sem setor, sem reescrever os dados históricos ou liberar arquivos já exportados.
- Migração 003 incremental, preservando dados, lotes, assinaturas dos arquivos e referências antigas.
- Recuperação de backup na primeira autenticação administrativa, antes da sincronização; protege conta/loja e mantém as permissões atuais.

Consulte LEIA_PRIMEIRO.md para instalação, SQL das contas e orientação sobre a nova assinatura do APK de teste.
