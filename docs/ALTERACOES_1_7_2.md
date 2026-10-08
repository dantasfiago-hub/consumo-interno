# Consumo Interno 1.7.2+13 — backups locais sem excesso

Causa: saveProduct, saveConsumption e cancel chamavam snapshot(force: true), ignorando a janela de 24 horas já definida no BackupController. Cada gravação gerava uma cópia completa e a retenção mantinha os 14 arquivos mais recentes.

Essas três rotinas agora chamam snapshot() e respeitam o intervalo de 24 horas desde o último backup local bem-sucedido. A primeira ação elegível ou sincronização após o intervalo produz a próxima cópia; não há promessa de execução com o aplicativo fechado. A configuração de desativar backup automático continua respeitada. A retenção permanece em até 14 cópias por vínculo/aparelho.

O registro no SQLite e na fila de sincronização continua imediato a cada lançamento. O intervalo entre backups significa que a última cópia pode ter até 24 horas; o banco local e a sincronização continuam recebendo os lançamentos atuais. Cópias forçadas permanecem para ativação, saída/troca de setor e comandos administrativos existentes. A política de backup remoto não foi alterada.

Arquivos existentes não são apagados pela atualização. A rotação continua ocorrendo na próxima cópia. Não exige SQL/migração nova. Atualize o código com git pull origin main, execute flutter pub get e recompile com o mesmo arquivo de conexão e chave Android.

## Validação

Inspeção da alteração confirmou somente três chamadas rotineiras convertidas; as chamadas forçadas de ativação/troca de setor foram preservadas. Não houve execução de testes Flutter ou compilação de APK/EXE nesta atualização.
