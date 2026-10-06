# Atualização 1.6.2+10

## Supabase já configurado com 007

Execute somente `supabase/migrations/008_multiple_sector_devices.sql` no SQL Editor. Não execute novamente schema.sql ou setup_sector_devices.sql. A migração conserva os aparelhos, códigos, consumos e exportações existentes. Ela não foi aplicada automaticamente ao projeto Supabase da loja.

## Várias máquinas no mesmo setor

1. Atualize o código e recompile o aplicativo.
2. Na administração, abra Aparelhos → Gerar código de ativação, escolha o setor e informe a justificativa.
3. Configure a nova instalação com URL, chave pública, UUID da loja e esse código. A primeira ativação exige internet.
4. Gere um código diferente para cada máquina adicional. Cada código vale 24 horas e só ativa uma instalação. Gerar outro código para o setor não invalida os códigos ainda válidos das outras máquinas.

O responsável pelo Supabase também pode adicionar uma máquina pelo SQL Editor:

```sql
SELECT public.provision_sector_device('UUID_DA_LOJA', 'cozinha', false);
```

Aceita `cozinha`, `padaria` e `hortifruti`. Sem e-mail ou cadastro de funcionários. Cada instalação conserva uma identidade técnica própria; não copie o banco ou as credenciais de uma instalação para criar outra.

## Revogar e substituir

Em Administração → Aparelhos, localize a identidade técnica da máquina e desative Acesso ativo em Editar acesso. Apenas essa identidade perde acesso. Sincronize e preserve pendências antes de revogar. Em seguida, gere um código adicional e ative a máquina nova.

A antiga opção de substituir por setor (`p_replace=true`) é recusada para os setores: ela não identifica qual máquina deve perder acesso. O aparelho administrativo conserva a recuperação existente, pelo SQL Editor, com substituição explícita; esta alteração permite múltiplas máquinas nos três setores.

## Dados e exportações

As máquinas do mesmo setor recebem os produtos e consumos compartilhados ao sincronizar e podem cancelar consumos do setor conforme as regras existentes. Offline, cada instalação mantém sua fila própria; as outras só recebem esses registros após sincronização. Dois cancelamentos sobre a mesma versão são tratados pelos controles de conflito existentes.

A exportação administrativa continua separada por setor e agrega os consumos sincronizados de todas as máquinas. Itens reservados ou já exportados continuam excluídos de novos lotes. Sincronize todas as máquinas antes de exportar para incluir seus lançamentos pendentes. As regras de acesso, unidades, preço e layout VR permanecem.

## Validação

A suíte SQL 008 verifica atualização de vínculos existentes, códigos antigos, três máquinas da cozinha, expiração, uso único, replay, setor fixo, revogação individual, isolamento dos dados, cancelamento entre máquinas do setor e exportação agrupada sem reexportação. Execute `npm ci` e `npm test` em `tests_backend`.

O tratamento de WebP estático foi testado com o arquivo original fornecido. Não houve execução nativa no Windows nem novo build APK nesta alteração.

