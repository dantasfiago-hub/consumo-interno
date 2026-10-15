# Conversão de gramas excedentes

O campo Gramas aceita números e somas inteiras acima de 999. A cada 1000 g, um quilograma é incorporado ao total. A persistência permanece em milésimos de kg, sem mudança de esquema ou arredondamento.

| Entrada | Resultado |
|---|---|
| 0 kg e 1500 g | 1 kg e 500 g |
| 2 kg e 1500 g | 3 kg e 500 g |
| kg 2+1 e gramas 800+700 | 4 kg e 500 g |
| 999 g e botão + | 1 kg e 0 g |
| 1 kg e 0 g e botão − de gramas | 0 kg e 999 g |

## Digitação e confirmação

A prévia mostra o peso total normalizado. Os campos são reorganizados quando Gramas perde o foco ou ao pressionar Enter. Isso preserva a digitação: converter enquanto a pessoa ainda está escrevendo 1500 poderia alterar o número antes do último dígito. Ao confirmar o item, o cálculo aceita e normaliza o excedente mesmo que o foco ainda esteja no campo.

Os botões de gramas aplicam mais/menos 1 g sobre o peso total e atualizam ambos os campos. No limite máximo de 999999999999 gramas o aumento é bloqueado; no zero, a diminuição é bloqueada. A confirmação continua exigindo peso positivo. Quilos, gramas e unidades continuam aceitando apenas inteiros nos campos separados, e dinheiro não foi alterado.

Expressões incompletas ou inválidas não são substituídas nem descartadas. Um peso combinado acima do limite é rejeitado. Quantidades UN permanecem sem campo de gramas.

## Aplicação e validação

Atualize o código e recompile Android/Windows. Não exige migração SQL. Nenhum APK/EXE foi gerado.

Executadas 48 verificações pelo script `dart run test/sum_expression_checks.dart`; análise estática do parser e desse script sem problemas. Fontes Dart formatados. Testes Flutter atualizados/adicionados para botões, normalização ao perder foco/Enter, expressão incompleta e limite; esses testes de interface não foram executados neste ambiente.
