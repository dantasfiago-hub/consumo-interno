# Versão 1.2.0

- Módulo Exportações separado dos relatórios, com domínio, casos de uso, contrato de repositório e telas próprias.
- Agrupamento por código, quantidade acumulada e preço ponderado com até quatro casas, usando BigInt/numeric.
- Bloqueio de itens cancelados, duplicados, reservados e códigos com unidades/identidades incompatíveis.
- Perfil versionado de TXT, exemplo fictício e confirmação de conferência no VR Master.
- Migração PostgreSQL aditiva, endpoints v2, arquivo imutável com SHA-256 e eventos idempotentes.
- Proteção anterior à gravação para evitar corrida entre cancelar e salvar; confirmação de salvamento com fila persistente.
- Confirmação manual de importação e preservação dos estados históricos anteriores.
- Favoritos e produtos recentes, mantidos offline e incluídos no backup junto do perfil.
- Remoção das ações fiscais da interface e atualização de relatórios/documentação.
- Tema escuro e imagens offline preservados.

## Limites desta entrega

O perfil do VR Master precisa ser conferido no sistema real da loja. A atualização da nuvem é fornecida como SQL; nenhuma conta externa foi alterada nesta execução. Windows precisa ser compilado no Windows. Estorno/correção de um lote cuja gravação já foi autorizada, migração de fotos para armazenamento de objetos e paginação avançada continuam como evolução futura.
