# Histórico de alterações — Consumo Interno

Do mais recente para o mais antigo. Para instalar ou atualizar, siga [LEIA_PRIMEIRO.md](LEIA_PRIMEIRO.md). Os detalhes de cada versão estão em `docs/`.

## Não lançado — revisão de código (novembro de 2026)

Correções propostas após revisão do repositório; ainda não compiladas nem publicadas. Nenhuma altera dados existentes.

### Novidade
- **Cozinha e Padaria lançam só a quantidade.** O campo "Valor total" deixa de aparecer nesses setores; o item é gravado com valor 0. Horti Fruti continua exigindo o valor.
  - Nova migração `013_quantity_only_sectors.sql`: o servidor passa a aceitar total 0 em Cozinha e Padaria (Horti Fruti segue exigindo valor positivo) e a gerar o arquivo de exportação desses setores (código e quantidade) mesmo com itens sem valor.
  - Lançamentos antigos mantêm o valor que já tinham. No histórico e nos relatórios, itens sem valor aparecem sem preço ("-" nos relatórios); a confirmação do lançamento deixa de mostrar o total nesses setores.
  - Novos testes: `tests_backend/quantity_only_v13_test.mjs` (migração 013, antes e depois, e exportação) e testes Dart de validação e preço unitário; o teste de interface de Padaria foi ajustado (sem campo de valor, total 0).

### Correções
- **Migração 012** idempotente (`add column if not exists`, `create index if not exists`): antes falhava em instalação nova porque o `schema.sql` já contém a coluna `revision`. Passo documentado em [LEIA_PRIMEIRO.md](LEIA_PRIMEIRO.md). Novo teste `tests_backend/fresh_install_v12_test.mjs` aplica `schema.sql` e todas as migrações em ordem e repete a 012.
- **Backup na nuvem** avaliado no máximo a cada 30 minutos (`_cloudBackupInterval`), em vez de serializar o banco inteiro a cada sincronização.
- **Fila de envio:** a rejeição permanente (erro 4xx, exceto 401, 408 e 429) de um consumo bloqueia só as operações da mesma entidade; os demais consumos continuam. Falhas de rede, 401, 408, 429, 5xx e operações de produto continuam interrompendo a fila. Nada é descartado.
- **Restauração de backup** deixa de ser quadrática, e a restauração da nuvem não carrega mais todos os registros só para verificar se o banco está vazio.
- **Senha administrativa:** a verificação usa o número de iterações gravado no registro (senhas antigas de 120 mil continuam válidas; novas usam 310 mil). O contador de tentativas é persistido, e o bloqueio dobra a partir da quinta falha, de 30 s até 15 min.
- **Data do lançamento** volta para hoje depois de salvar e ao reabrir o app (sem itens e sem data escolhida); a confirmação avisa quando a data não é a de hoje.
- **Troca de setor** com itens no lançamento (administrador) pede confirmação antes de removê-los.
- **Mensagens de erro** sem prefixos técnicos (`friendlyError`); timeouts de rede têm mensagem própria.
- **Busca sem acentos** no seletor de produtos, na lista de produtos e nos filtros de relatório.
- **URLs do Supabase:** valores interpolados passam por `Uri.encodeQueryComponent`.

### Documentação
- Criado este `CHANGELOG.md`, que reúne o histórico antes espalhado pelo README e por `LEIA_PRIMEIRO.md`. `LEIA_PRIMEIRO.md` passa a ser apenas o guia de instalação e atualização.

### Para quem atualiza
**Execute a migração 013 no Supabase antes de distribuir o aplicativo novo.** Sem ela, o servidor recusa os lançamentos de Cozinha e Padaria sem valor, e a sincronização desses aparelhos fica com pendência. Em loja existente, execute também a 012 se ainda não executou. Recompile todos os aparelhos. O tempo de desbloqueio da senha administrativa deve ser medido no aparelho mais lento (`adminPasswordIterations`).

## 1.7.6+17 e alterações sem mudança de número

As seções abaixo foram mantidas na ordem em que constavam no README, da mais recente para a mais antiga.

### Correção de bloqueio do banco local

A conexão SQLite agora usa WAL e espera até 5 segundos por bloqueios transitórios. A abertura de produção obtém exclusividade por instalação para impedir que duas cópias atualizadas do aplicativo disputem a mesma base e a área de recebimento da sincronização. Uma segunda abertura mostra orientação para fechar a outra janela. Feche todas as instâncias antigas antes de usar a nova compilação. A correção preserva o arquivo existente, registros e fila de envio; não exige SQL Supabase. Veja [o guia](docs/BANCO_LOCAL_BLOQUEADO.md).

### Conversão de gramas excedentes

Gramas acima de 999 agora contribuem automaticamente para os quilos: `2 kg + 1500 g = 3 kg e 500 g`. A prévia acompanha a digitação; ao sair do campo de gramas ou pressionar Enter, os campos são normalizados. Confirmar o item também calcula o peso correto, mesmo sem sair do campo. O botão + passa de 999 g para o próximo kg; o botão − pode retornar de 1 kg e 0 g para 999 g. Somas incompletas são preservadas e o limite total continua validado. Recompile para aplicar; não exige SQL. Veja [os detalhes](docs/GRAMAS_EXCEDENTES.md).

### Correções de logout e histórico

Logout legado remove os tokens antigo e por loja e bloqueia o acesso local sem
apagar pendências. O histórico carrega 50 registros por vez com **Carregar mais**;
a busca inclui registros antigos. Relatórios e exportações consultam os dados
completos sob demanda, preservando totais e reservas além da primeira página.
O SQLite recebe um índice automaticamente; não exige novo SQL no Supabase.
Veja [as alterações](docs/CORRECOES_LOGOUT_HISTORICO.md) e o
[guia de configuração local](config/README.md).

### Administração de aparelhos por setor

Administração → Aparelhos atualiza a lista ao abrir e permite filtrar todos os setores ou Administração/Horti Fruti/Cozinha/Padaria. Mostra identificação, ativação e número de vínculos autorizados. **Excluir acesso** exige confirmação, revoga somente a máquina selecionada e preserva produtos, consumos e backups. O último administrador continua protegido; a própria máquina deve usar Sair ou trocar de setor. Aplique [011_admin_device_listing.sql](supabase/migrations/011_admin_device_listing.sql) após 010 para os metadados e recompile. [Guia](docs/GESTAO_APARELHOS.md).

### Relatórios por produto

A página abre sem resultados. Selecione os filtros e pressione **Aplicar filtros**, ou use **Exibir histórico completo** para consultar confirmados e cancelados de todos os períodos/setores sem apagar os filtros preenchidos. **Aplicar filtros** encerra o modo histórico completo e usa novamente os filtros do formulário. Sem critérios preenchidos, esse botão volta à página sem resultados; a situação padrão Confirmados sozinha não conta como pesquisa. Alterar um filtro oculta os resultados até aplicar novamente. Em seguida, ative **Agrupar por produto** para somar quantidades e valores dos registros filtrados. A tela, o CSV e o PDF usam o mesmo agrupamento e mostram também a quantidade de lançamentos. UN e KG, produtos distintos e confirmados/cancelados são separados. Recompile para aplicar; não exige SQL. Veja [os detalhes](docs/RELATORIO_POR_PRODUTO.md).

### Tema escuro — cinza mais claro e verde escuro

O tema escuro agora usa fundo cinza médio, cartões mais claros, campos cinza escuro e botões verde floresta com texto branco. Links e indicadores usam verde claro para preservar o contraste. A paleta central é aplicada a todos os setores e à administração. Recompile para aplicar; não exige SQL e não inclui novos APK/EXE. Veja [os detalhes](docs/TEMA_CINZA_VERDE.md).

### Atualização 1.7.6 — retenção de backups

Mantém até quatro cópias locais por vínculo e duas cópias na nuvem por loja/identidade/aparelho. O intervalo automático local continua em sete dias; cópias forçadas permanecem. Execute [010_backup_retention.sql](supabase/migrations/010_backup_retention.sql) após 009 e recompile o aplicativo. A migração elimina as cópias remotas excedentes, preservando as duas mais recentes; a limpeza local ocorre após o próximo backup bem-sucedido. O texto de Configurações foi corrigido. Veja [o guia](docs/ALTERACOES_1_7_6.md).

### Atualização 1.7.5 — filtro de produtos por setor

Produtos na administração permite selecionar Todos os setores, Horti Fruti, Cozinha, Padaria ou Sem setor. O filtro combina com busca por código/descrição, UN/KG, favoritos e inclusão de inativos. Produtos compartilhados aparecem em cada setor atribuído. Funciona com os dados locais, sem nova migração SQL. Os setores continuam com acesso apenas aos seus módulos/produtos. Recompile para aplicar; esta alteração não inclui novos APK/EXE.

### Atualização 1.7.4 — tema para todos os setores

O botão Alterar tema no topo do aplicativo permite escolher Claro, Escuro ou Automático em qualquer setor, sem entrar nas configurações administrativas. A preferência fica salva no aparelho e funciona offline. Os setores continuam com os módulos de lançamento/cancelamento; permissões administrativas não foram alteradas. Recompile para aplicar; não exige SQL. Veja [o guia](docs/ALTERACOES_1_7_4.md).

### Atualização 1.7.3 — backups locais semanais

O intervalo automático local agora é de sete dias desde a última cópia bem-sucedida. A próxima cópia é criada quando houver uso/sincronização após esse prazo; o aplicativo fechado não executa backups. Mantém até 14 cópias por vínculo. Backup manual, ativação e saída/troca de setor continuam podendo gerar cópias adicionais. Backups remotos não foram alterados. Não exige SQL; recompile para aplicar. Veja [o guia](docs/ALTERACOES_1_7_3.md).

### Atualização 1.7.2 — frequência de backups locais

Lançamentos, cancelamentos e cadastros deixam de forçar uma cópia completa a cada gravação. O backup automático respeita o intervalo existente de 24 horas, mantendo até 14 cópias locais. As gravações no SQLite continuam imediatas; ativação, saída/troca de setor e backup manual mantêm suas cópias forçadas. Backups antigos não são apagados por esta atualização. Não exige migração SQL. Veja [o guia](docs/ALTERACOES_1_7_2.md).

### Atualização 1.7.1 — soma nos campos do consumo

Quantidade e valor total aceitam adição sem sinal de igual: `10+20+5`. O resultado aparece enquanto se digita. Kg, gramas e UN aceitam parcelas inteiras; valor total aceita até duas casas por parcela, com vírgula ou ponto decimal. Kg e gramas continuam separados, e a soma de gramas não pode exceder 999. Os botões +/− resolvem a expressão antes de alterar 1; expressões incompletas bloqueiam esses botões e a inclusão do item. Somente o resultado numérico é persistido. Não exige migração SQL. Recompile para usar; esta atualização não inclui APK/EXE novos. Veja [o guia](docs/ALTERACOES_1_7_1.md).

### Atualização 1.7 — conexão incorporada, QR e troca de setor

A conexão padrão pode ser incorporada com `--dart-define-from-file=config/connection.local.json`, mantendo os campos editáveis. A administração gera código e QR de ativação para setores ou administradores adicionais. Android lê pela câmera; Windows/Android podem abrir a imagem PNG. O botão Sair ou trocar de setor sincroniza e grava backup antes de retornar à ativação. Um código novo autoriza a troca; pendências bloqueiam a saída e o último administrador permanece protegido.

Aplique 009 após 008. Leia [o guia 1.7](docs/ALTERACOES_1_7.md). Os valores reais da conexão ainda precisam ser configurados. Não foram gerados novos binários nesta alteração.

### Atualização 1.6.2 — várias máquinas por setor

Aplique [008_multiple_sector_devices.sql](supabase/migrations/008_multiple_sector_devices.sql) após 007. Cada novo código ativa uma máquina adicional, sem desconectar as anteriores. Os códigos valem 24 horas e são de uso único. Revogue uma máquina individualmente em Administração → Aparelhos. Produtos e consumos continuam restritos ao setor; sincronização, cancelamentos e exportações usam os dados compartilhados. Consulte [o guia da atualização](docs/ALTERACOES_1_6_2.md).

Também inclui a correção de fotos WebP estáticas. Fonte 1.7.6+17; não foi gerado um novo APK ou EXE nesta alteração. O APK 1.6.1 citado abaixo é da entrega anterior.

### Correção Android 1.6.1

Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.21 e Java 17. SDK 36 e NDK 28.2.13676358 fixados. Guia completo: [Compilar Android](docs/COMPILAR_ANDROID.md). A assinatura real fica fora do GitHub; `android/key.properties.example` serve somente como modelo. GitHub Actions executa os testes e gera APK debug.

### Atualização 1.6 — aparelho por setor, sem e-mail

O administrador ativa cada aparelho com um código de uso restrito ao setor. Depois, os funcionários abrem diretamente Lançar consumo, sem nome, e-mail ou login diário. O setor é fixo; produtos e consumos continuam isolados. O aparelho administrativo usa senha local própria, inclusive offline.

Habilite Anonymous Sign-Ins no Supabase, aplique 007, 008 e 009 após 006 e siga [LEIA_PRIMEIRO.md](LEIA_PRIMEIRO.md). Loja nova pode usar `supabase/setup_sector_devices.sql` para gerar os quatro códigos iniciais. Não é necessário criar contas de funcionários: o Auth cria identidades técnicas automaticamente. Troca de aparelho deve preservar pendências antes de revogar o antigo.

As exportações por setor, controles kg/gramas/UN e confirmações da 1.5 permanecem. Atualização do fonte: 1.7.6+17; APK anterior release 1.6.1+9 compilado e assinatura verificada. Não foi compilado EXE Windows nesta entrega.

## 1.5.0+7 e anteriores (resumo; detalhes nos guias)

### 1.5.0+7 — exportação por setor
Arquivos de Cozinha e Padaria contêm somente código interno e quantidade acumulada; Horti Fruti mantém os quatro campos. Registros e relatórios continuam armazenando valores. Veja [docs/ALTERACOES_1_5.md](docs/ALTERACOES_1_5.md).

### 1.4.1+6 — revisão corretiva
Gravação, sincronização, restauração, permissões, fotos e auditoria. Veja [docs/ALTERACOES_1_4_1.md](docs/ALTERACOES_1_4_1.md) e [docs/REVISAO_CODIGO_1_4_1.md](docs/REVISAO_CODIGO_1_4_1.md).

### 1.4.0+5 — controladores e administração
`AppState` passa a compor controladores de sessão, catálogo, consumo, sincronização, backup e administração; sincronização sem concorrência local, com retentativa progressiva; administração de vínculos; pendências com revisão; auditoria central; backups automáticos locais. Veja [docs/ALTERACOES_1_4.md](docs/ALTERACOES_1_4.md).

### 1.3.0+4 — isolamento de setores
Acesso restrito por setor (lançamento/cancelamento e produtos do próprio setor), RLS e operações SQL conferindo o setor, produto em mais de um setor, exportação administrativa por setor. Veja [docs/ALTERACOES_1_3.md](docs/ALTERACOES_1_3.md).

### 1.2.0 — módulo de exportações
Módulo Exportações separado dos relatórios, agrupamento por código com preço ponderado, perfil versionado de TXT, arquivo imutável com SHA-256 e migração PostgreSQL aditiva. Veja [docs/ALTERACOES_1_2.md](docs/ALTERACOES_1_2.md).

### 1.1 — modularização e aparência
Código separado por funcionalidade e tema claro/escuro/automático. Veja [docs/ALTERACOES_1_1.md](docs/ALTERACOES_1_1.md).
