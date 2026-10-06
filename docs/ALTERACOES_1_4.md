# Alterações — 1.4.0+5

- `AppState` passa a compor controladores específicos de sessão, catálogo, consumo, sincronização, backup e administração.
- Sincronização sem concorrência local, retentativa progressiva e envio manual imediato.
- Administração de vínculos de contas existentes: papel, setor, ativação e proteção do último administrador.
- Pendências centralizadas com revisão, justificativa, tentativa original arquivada e aplicação restrita às regras vigentes. Exportações não são desfeitas pela revisão.
- Auditoria central de operações, exportações, vínculos e revisões, com filtros e páginas de histórico.
- Backups automáticos locais com escrita atômica/checksum e retenção de 14 cópias; remotos comprimidos com 7 cópias por conta/dispositivo e recuperação de instalação vazia autorizada.
- Fotos separadas dos metadados, deduplicadas por hash e baixadas incrementalmente com isolamento por setor.
- Conferência por setor em Exportações: disponíveis, protegidos e pendências; aviso de itens ignorados na reserva.
- Ícone original aplicado ao Android, Windows e interface. Temas claro/escuro/sistema mantidos.
- APK release ARM64 com chave permanente; kit privado separado do código, scripts e workflow preparados para preservar a assinatura.

Aplicar 004 após 003. Sincronizar todos os aparelhos e guardar backups antes de migrar dos APKs de teste. As regras de acesso dos setores, unidade exportada `1`, cálculo de até quatro casas e proteção contra reexportação permanecem.
