# Histórico de alterações — Consumo Interno

## Não lançado

### Novidade
- **Leitura de etiquetas de balança no lançamento.** Câmera Android, código digitado/colado ou leitor USB identificam o produto pelo código interno; OCR local tenta ler o peso líquido. O usuário revisa produto, quantidade e valor antes de adicionar. Etiquetas repetidas podem somar à quantidade existente.
  - O layout padrão é EAN-13 com prefixo `2`, 6 dígitos de código interno e 5 dígitos de valor em centavos. Administradores podem ajustar prefixo, comprimentos e campo numérico em Configurações; a preferência fica somente no aparelho.
  - OCR usa processamento local apenas no Android. Se não houver OCR, a quantidade fica para digitação; imagens não são gravadas nem enviadas. Não exige migração ou mudança no Supabase.
