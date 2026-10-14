# Correções de regressão — 14/10/2026

- Backup manual/forçado funciona mesmo com backup automático desativado. Cópias obrigatórias continuam propagando falhas para bloquear saída/troca insegura.
- Intervalo semanal considera a pasta e o vínculo após a primeira cópia nesta versão. A configuração histórica sem marcador de pasta preserva seu prazo na atualização.
- Relógio futuro inválida o prazo em vez de bloquear cópias indefinidamente; nomes monotônicos preservam a cópia nova quando o relógio retrocede. Chamadas simultâneas não sobrescrevem arquivos com mesmo timestamp.
- Rotação local mantém quatro cópias com nomes gerados pelo aplicativo, preservando JSONs de outros nomes. Restauração bem-sucedida reinicia o prazo para que os dados restaurados recebam uma nova cópia.
- Corrigida expectativa antiga de 14 cópias. Adicionadas verificações de sete dias, opt-out/manual, restauração, erro/retry, vínculo/pasta, concorrência e relógio.
- Testes da Shell verificam seletor de tema, preservação de observação e permissões nos três setores, em 390/1280px. Fluxo de UI usa somas com kg/gramas/centavos e verifica aplicação/limpeza de filtros do relatório.
- Backend testa Base64 inválido e carga acima de 20 MB. Seu job de CI roda independentemente de Flutter; builds exigem ambas as validações.
- Corrigido warning de quantidade. Scripts Dart autônomos têm exceções locais justificadas para imports relativos/print; os demais arquivos permanecem sob os lints.

Não exige migração SQL adicional. Mantém sete dias, quatro cópias locais e duas remotas (migração 010 existente). Nenhum SQL foi aplicado à loja.

Validação local: npm test aprovado (11 suítes); parser Dart aprovado (36 verificações); git diff --check aprovado. Validação Flutter e builds devem ser conferidos no CI da PR. A inicialização local do SDK foi bloqueada por revisão automática ao tentar acessar metadados da infraestrutura. Testes físicos Android/Windows e concorrência de duas sessões PostgreSQL permanecem na checklist de homologação.
