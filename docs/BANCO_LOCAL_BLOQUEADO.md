# SQLite: database is locked

## Sintoma e diagnóstico

A tela mostrou SQLiteException(5), database is locked, ao inserir na tabela local incoming durante a sincronização. O erro é de concorrência/acesso ao SQLite local. O código anterior não configurava tempo de espera nem garantia uma instância por instalação. A captura não permite identificar qual processo manteve o bloqueio.

## Correção

- A conexão de produção configura busy_timeout=5000 e journal_mode=WAL no isolate do banco, antes das migrações e consultas.
- WAL permite leitores durante gravações; o SQLite continua permitindo um escritor por vez.
- A espera permite que um bloqueio transitório termine antes de retornar erro. Bloqueios superiores a 5 segundos ainda podem causar erro e devem ser investigados.
- Um bloqueio do sistema operacional no arquivo consumo.sqlite.lock impede duas instâncias atualizadas do aplicativo de acessar a mesma base local. O bloqueio é mantido até fechar o banco ou encerrar o processo; a simples presença do arquivo não significa bloqueio ativo.
- O arquivo de lock não deve ser apagado para tentar liberar acesso: o processo detentor precisa ser encerrado. Nunca apague consumo.sqlite ou seus arquivos -wal/-shm.
- O processo secundário mostra uma mensagem e não inicia sincronização. Uma versão antiga não conhece esse bloqueio; feche todas as versões antigas antes de testar.
- Os aparelhos de outros computadores/setores continuam independentes e sincronizam normalmente com a nuvem. Esta exclusividade é por base local, não por setor ou loja.

## Atualização

Feche todas as janelas do aplicativo. Atualize o código e recompile. Abra somente a nova versão. Em caso de processo em segundo plano no Windows, confirme no Gerenciador de Tarefas e encerre o Consumo Interno antes de reabrir.

A mudança mantém os registros, preferências e operações pendentes e não altera a versão do esquema local nem exige migração Supabase. Não desinstale nem restaure um backup para solucionar esse erro. Não foi gerado novo APK/EXE.

## Validação

Executados com Dart standalone e Drift 2.28.2/SQLite:
- Dois processos: rejeição da segunda instância, reabertura após liberar, recuperação após término abrupto e fechamento idempotente.
- Duas conexões em isolates: WAL e espera em ambas, leitor com gravação pendente, segundo escritor aguardando e concluindo, e rollback sem gravação parcial.
- Análise estática dos novos auxiliares e verificadores sem problemas; arquivos Dart formatados.

Adicionado teste Flutter para abrir uma base existente, preservar dados e aplicar incoming/cursor pela conexão de produção; também integra o teste de concorrência à suíte. A suíte Flutter e a execução no Windows não foram realizadas neste ambiente.
