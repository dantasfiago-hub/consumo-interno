# Consumo Interno 1.7.3+14 — backups locais semanais

O intervalo automático local passa de 24 horas para sete dias desde o último backup bem-sucedido. O próximo backup ocorre durante uso/sincronização após esse prazo, não em horário fixo e não com o aplicativo fechado. A retenção permanece em até 14 arquivos por vínculo/aparelho.

Cópias manuais, ativação e saída/troca de setor continuam forçadas quando aplicável. O último backup forçado também reinicia o prazo automático. O banco SQLite grava cada lançamento imediatamente; entre cópias, os registros recentes permanecem no banco e na sincronização, mas podem não constar na última cópia de segurança. Backups remotos mantêm sua política anterior.

Não exige migração SQL. Atualize o código e recompile os aparelhos com a mesma conexão e chave de assinatura. Os backups existentes são preservados e a rotação continua na próxima cópia.

Validação: revisão do intervalo e das condições que preservam cópias forçadas. Não foram executados testes Flutter nem gerados APK/EXE nesta alteração.
