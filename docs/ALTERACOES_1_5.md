# Alterações — 1.5.0+7

## Exportação por setor

Novos arquivos de Cozinha e Padaria contêm somente código interno e quantidade acumulada. Horti Fruti mantém os quatro campos anteriores. Os registros e relatórios continuam armazenando valores. Agrupamento por produto, preservação dos zeros iniciais e exclusão de consumos reservados/exportados continuam ativos.

Exemplos com o perfil padrão, sem cabeçalho:

```text
Cozinha/Padaria: 000125;2,35
Horti Fruti:    000125;2,35;1;30
```

Os rótulos acima são explicativos e não fazem parte do TXT. Separador/decimal/codificação/fim de linha seguem o perfil configurado. A ordem dos dois campos é fixa; a ordem dos quatro campos segue o perfil de Horti Fruti. A migração 006 adapta também pedidos de novos lotes feitos por clientes anteriores. Reenvio/download de um lote existente preserva o arquivo histórico; não converte arquivos já gerados.

## Entrada e confirmações

- KG: campos inteiros de quilogramas e gramas (0–999), combinados em milésimos sem ponto flutuante.
- Botões para aumentar/diminuir 1 kg, 1 g ou 1 unidade, com limites e piso zero.
- Confirmação do consumo com responsável, data, setor, quantidades e valores, antes da gravação.
- Confirmação antes da reserva e antes da autorização/salvamento do arquivo para o VR. Voltar não executa a ação.
- Rascunho permanece quando o usuário volta da confirmação. Não há mudança nas permissões dos funcionários.

## Atualizar

Aplicar `supabase/migrations/006_sector_export_quantity.sql` depois de 005. Não reaplicar o esquema base. Recompilar Android/Windows; Android usa a mesma chave release e código 7. Não foi gerado APK/EXE nesta entrega nem houve importação real no VR.

82 testes Flutter e seis suítes SQL aprovados; análise estática sem ocorrências. Evidências em `docs/validation/`.
