# Consumo Interno 1.7.1+12 — soma durante o lançamento

Nos campos de quantidade e valor total, escreva parcelas separadas por +, sem colocar =. Exemplos: UN 10+20+5 resulta em 35; kg 2+1 com gramas 200+150 resulta em 3,350 kg; valor 10,50+20+5 resulta em R$ 35,50.

O resultado é atualizado abaixo de cada campo. O valor total pertence ao mesmo produto; não é multiplicado novamente pela quantidade. Ao adicionar o item e confirmar o consumo, o banco recebe apenas a quantidade em milésimos e o valor em centavos. A expressão não é armazenada.

- Kg, gramas e UN continuam inteiros em seus campos separados.
- A soma das gramas deve ser de 0 a 999. Para mais peso, distribua entre kg e gramas.
- Valores aceitam vírgula ou ponto decimal e até duas casas por parcela.
- Operação suportada: adição de números não negativos. Não há subtração, multiplicação, funções ou referências de células.
- Expressões com parcelas ausentes (10+), letras, =, precisão excessiva ou soma acima do limite são recusadas. Zero pode aparecer durante a edição, mas quantidade e valor finais devem ser positivos.
- Os botões de quantidade calculam a soma e substituem o campo pelo resultado acrescido/diminuído de 1. Uma expressão inválida não é descartada pelos botões.
- O teclado de texto permite digitar + no Android. O campo tem limite de 200 caracteres.

## Atualizar

Não exige nova migração SQL; preserve as migrações existentes até 009. Na pasta do projeto, atualize com git pull origin main e flutter pub get. Recompile com a configuração de conexão existente:

```powershell
flutter build apk --release --dart-define-from-file=config/connection.local.json
flutter build windows --release --dart-define-from-file=config/connection.local.json
```

Android release usa a mesma chave privada anterior. Compile Windows no Windows. Nenhum APK/EXE novo foi gerado nesta alteração.

## Validação

Executadas 36 verificações Dart independentes para cálculos exatos, unidades, pesos, entradas inválidas e limites. Análise estática do cálculo e dessas verificações sem ocorrências. Os testes Flutter de interface foram adicionados, mas não executados neste ambiente; executar flutter test no ambiente de desenvolvimento/CI. Não houve teste em aparelho físico.
