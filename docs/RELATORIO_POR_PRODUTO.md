# Relatório agrupado por produto

## Uso

Na administração, abra Relatórios: inicialmente só os controles de consulta são exibidos, sem totais, registros ou botões de exportação. Selecione período, setor, produto, unidade e situação, e pressione **Aplicar filtros**. Ao editar qualquer filtro, os resultados ficam ocultos até aplicar novamente; valores inválidos bloqueiam a aplicação.

**Exibir histórico completo** abre uma consulta sem restrições de período, setor, unidade ou situação, incluindo confirmados e cancelados. Os filtros preenchidos e seus erros de validação são preservados no formulário. A indicação Histórico completo aparece enquanto esse modo está ativo. **Aplicar filtros** desativa esse modo e retorna aos filtros preenchidos; filtros inválidos devem ser corrigidos antes de aplicar. CSV/PDF seguem a consulta exibida, mesmo que o formulário preservado tenha erros durante o modo completo. Totais de consumo válido continuam excluindo cancelados. Para somar por produto, ative **Agrupar por produto** depois de consultar. Cada linha mostra código, descrição, quantidade total, unidade, valor total e número de lançamentos. Os botões CSV/PDF acompanham o modo selecionado. Desative o agrupamento para retornar ao detalhamento.

## Regras

- Os filtros são aplicados antes da soma. Os limites mínimo/máximo de valor continuam filtrando cada item original, não o total agrupado.
- Agrupa pela identidade do produto, unidade e situação; produtos diferentes com o mesmo código não são mesclados.
- Consumos de setores diferentes são somados quando nenhum setor é filtrado.
- KG e UN são separados, assim como confirmados e cancelados. Os indicadores gerais e o total confirmado do PDF excluem cancelamentos.
- Quantidades usam milésimos e dinheiro usa centavos inteiros; a soma não arredonda cada lançamento.
- Usa código e descrição do registro mais recente dentro dos filtros, preservando os registros históricos.
- Arquivos recebem o prefixo `consumos_por_produto_`. CSV preserva código textual e proteção contra fórmulas.
- Relatórios permanecem exclusivos do administrador e funcionam com os dados locais.
- O relatório não reserva lançamentos nem altera as exportações para o VR.

## Instalação e validação

Atualize o código e recompile. Não exige migração Supabase. Nenhum APK/EXE novo foi compilado.

Executado: `dart run tools/verify_report_grouping.dart`, com verificações de somas, filtros, unidades, cancelamentos, ordenação e CSV. Análise estática do domínio e desse verificador sem problemas. Fontes Dart formatados. A interface Flutter e a geração PDF não foram executadas neste ambiente.

A atualização da aplicação explícita dos filtros foi revisada e formatada; a interação da interface não foi executada neste ambiente.

Correção da saída do histórico completo: fonte revisado e formatado; não houve execução da interface Flutter.

## Aplicar sem filtros

Aplicar filtros sem critérios encerra o histórico completo e oculta registros, totais e exportações, voltando à orientação inicial. A situação padrão Confirmados, ou Todos, sozinha não conta como pesquisa. Período, código/descrição, setor, unidade, limites de valor (inclusive zero) ou situação Cancelados contam como critérios. Para consultar todos os registros, use Exibir histórico completo. Esse comportamento altera apenas a visualização; não apaga dados. Fonte formatado e revisado; interação Flutter não executada.
