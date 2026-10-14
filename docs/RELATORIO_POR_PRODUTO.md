# Relatório agrupado por produto

## Uso

Na administração, abra Relatórios, selecione período, setor, produto, unidade e situação, e ative **Agrupar por produto**. Cada linha mostra código, descrição, quantidade total, unidade, valor total e número de lançamentos. Os botões CSV/PDF acompanham o modo selecionado. Desative o agrupamento para retornar ao detalhamento.

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
