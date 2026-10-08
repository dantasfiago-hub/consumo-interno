# Instalação — Consumo Interno 1.7.2+13

Veja [o guia completo da versão 1.7](docs/ALTERACOES_1_7.md) para incorporar a conexão, ativar por QR e sair/trocar de setor. O fonte foi atualizado; os binários anteriores não incluem estas alterações.

A versão 1.7.2 corrige os backups excessivos durante lançamentos: cópias automáticas respeitam 24 horas, mantendo até 14 arquivos. Não exige nova migração; recompile os aparelhos. Veja docs/ALTERACOES_1_7_2.md.

A versão 1.7.1 permite somar nos campos do lançamento sem `=` (ex.: `10+20+5`). Não exige nova migração de banco. Veja docs/ALTERACOES_1_7_1.md e recompile os aparelhos.

## Supabase existente

Se já aplicou 008, execute somente `supabase/migrations/009_activation_and_scope_changes.sql` no SQL Editor. Se a última migração foi 007, execute 008 e depois 009. Não reaplique schema.sql nem setup_sector_devices.sql na loja existente.

## Supabase novo

1. Crie o projeto e habilite Authentication → Allow anonymous sign-ins.
2. Execute schema.sql e todas as migrações 002 a 009, nessa ordem.
3. Execute uma única vez setup_sector_devices.sql, alterando o nome da loja. Guarde o UUID e os códigos iniciais de uso único, válidos por 24 horas.
4. Ative o aparelho administrativo. Sem configuração incorporada, preencha URL HTTPS, chave pública e UUID da loja, junto com o código administrativo. Defina a senha local.
5. Na administração, gere códigos/QRs para os demais aparelhos. Cada aparelho tem um código próprio; pode haver várias máquinas por setor e vários administradores.

Não é necessário criar funcionários ou e-mails. O Supabase cria identidades técnicas anônimas. Não apague essas identidades enquanto os aparelhos dependerem delas. Não use service_role ou sb_secret_ no aplicativo.

## Atualizar e compilar

```text
git pull origin main
flutter pub get
flutter analyze
flutter test
```

Para deixar a conexão incorporada, configure `config/connection.local.json` e use `--dart-define-from-file=config/connection.local.json` ao compilar. O modelo está em config/connection.example.json. Android release exige o kit de assinatura privado existente; Windows exige Flutter e Visual Studio C++ no Windows. A pasta supabase pode permanecer no projeto; os SQL precisam ser executados separadamente na nuvem.

Os setores continuam acessando apenas lançamento/cancelamento e seus produtos. A exportação administrativa reúne registros sincronizados por setor, ignorando os já reservados/exportados. Cozinha/Padaria exportam código e quantidade; Horti Fruti mantém os quatro campos. Sincronize todas as máquinas antes de exportar.

Para trocar de setor/loja, use Sair ou trocar de setor e um novo código autorizado. A saída exige sincronização concluída e backup local. Os dados antigos permanecem na nuvem e na cópia local; os rascunhos ainda não lançados são descartados com confirmação. Não apague banco ou credenciais para contornar pendências.

Não foi aplicado SQL à loja nem compilado um novo APK/EXE nesta entrega. As limitações de validação estão registradas no guia 1.7.
