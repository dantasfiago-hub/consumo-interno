# Instalação — Consumo Interno 1.6.1+9

Correção de compilação Android: Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.21, Java 17, API 36 e NDK 28.2.13676358. Consulte `docs/COMPILAR_ANDROID.md` para instalação do SDK sem Android Studio e assinatura.

Cada setor utiliza um aparelho fixo, sem e-mail, cadastro de funcionário ou login diário. Produtos e consumos continuam restritos a Horti Fruti, Cozinha ou Padaria. O aparelho administrativo usa senha própria.

Esta entrega contém código-fonte, scripts e APK release 1.6.1+9 compilado com a chave existente, com assinatura verificada. O APK anterior 1.4.0+5 não inclui estas mudanças. Não foi compilado EXE Windows. Para recompilar, use a mesma chave release e código de versão 9. Nenhuma migração foi aplicada ao Supabase da loja por esta entrega.

## Supabase novo

1. Crie um projeto Supabase e guarde URL HTTPS e chave pública `sb_publishable_...`. Nunca use `service_role` ou `sb_secret_...` no aplicativo.
2. Nas configurações do Authentication, habilite **Allow anonymous sign-ins**. O aplicativo cria automaticamente uma identidade técnica para cada aparelho, sem e-mail. Não crie contas de funcionários manualmente. Esses usuários técnicos aparecem em Authentication → Users; não os apague enquanto os aparelhos dependem deles.
3. No SQL Editor, execute o conteúdo dos arquivos, um por vez, nesta ordem:

```text
supabase/schema.sql
supabase/migrations/002_exports_v2.sql
supabase/migrations/003_sector_access.sql
supabase/migrations/004_operations_admin_media.sql
supabase/migrations/005_review_fixes.sql
supabase/migrations/006_sector_export_quantity.sql
supabase/migrations/007_sector_devices.sql
```

4. Execute **uma vez**, somente para loja nova, `supabase/setup_sector_devices.sql`. Altere o nome do supermercado. O resultado contém `uuid_da_loja` e quatro códigos: administrativo, Horti Fruti, Cozinha e Padaria. Cada código vale 24 horas; mantenha-o reservado para o aparelho correspondente.
5. No aparelho administrativo, abra Configuração inicial da loja e informe URL, chave pública, UUID da loja e o código administrativo. Toque em Ativar aparelho. Em seguida, defina e confirme uma senha administrativa de 8 a 128 caracteres.
6. Em cada aparelho de setor, informe as mesmas informações da loja e o código daquele setor. Não existe escolha livre de setor no aparelho. Após ativar, ele abre diretamente Lançar consumo, inclusive sem internet.

O código autoriza o vínculo; a chave pública sozinha não concede acesso aos dados. Os SQL criam tabelas, RPCs e RLS. Não é necessário bucket Storage ou Edge Function nesta implementação. O cliente usa o endpoint anônimo sem widget CAPTCHA; se seu projeto exigir CAPTCHA, será necessário integrar o desafio/token antes da ativação. Os limites de criação de identidades do Supabase continuam aplicáveis.

## Loja já configurada

Não reaplique `schema.sql` nem o script que cria a loja. Preserve backups e sincronize os aparelhos antes de atualizar. Para banco 1.5, aplique somente 007; banco 1.4.1 precisa de 006 e 007; banco 1.4.0 precisa de 005, 006 e 007. Instalações anteriores precisam das migrações anteriores em ordem.

Sessões existentes continuam renovando a credencial armazenada, sem novo login por e-mail. O programa não reescreve dados históricos. Administradores vinculados passam a definir senha local no primeiro acesso à nova versão.

Para gerar um código inicial numa loja existente, use o SQL Editor, substituindo o UUID:

```sql
SELECT public.provision_sector_device(
    'UUID_DA_LOJA', 'admin', false
);
```

O mesmo comando aceita `hortifruti`, `cozinha` e `padaria`. Não crie outro administrador ou usuário anônimo manualmente. O aparelho vinculado reutiliza sua credencial ao ativar. Se houver outros vínculos antigos do mesmo setor, revogue-os primeiro em Administração → Aparelhos; o servidor recusa ativação que manteria múltiplos vínculos.

## Códigos e substituição

Administração → Aparelhos → Gerar código de ativação permite escolher setor e informar justificativa. Se ele já tiver aparelho ativado, é necessária a opção explícita **Substituir aparelho existente**. Não ative essa opção sem sincronizar e preservar as pendências do aparelho anterior. O vínculo anterior perde acesso na próxima conexão.

Para renovar código ainda não usado/expirado, gere outro para o setor. O código anterior deixa de funcionar. Código usado não ativa outra identidade ou instalação.

Administradores iniciais ou recuperação administrativa são configurados pelo responsável pelo projeto no SQL Editor. Para recuperar uma senha administrativa esquecida, preserve os dados e gere um código administrativo novo com substituição explícita:

```sql
SELECT public.provision_sector_device(
    'UUID_DA_LOJA', 'admin', true
);
```

No **mesmo aparelho vinculado**, toque em Recuperar com novo código de ativação e informe o código. A credencial técnica original é reutilizada e a nova senha poderá ser definida. O código usado anteriormente não apaga uma senha já estabelecida.

## Uso diário

- Aparelho do setor: abre Lançar consumo. Só tem Lançar/Cancelar e produtos daquele setor; não informa e-mail, nome ou senha diária.
- Administração: senha ao reabrir, retornar do segundo plano ou tocar em Bloquear administração. O desbloqueio funciona offline; a credencial de sincronização continua preservada.
- Setor fica fixo. Não há cadastro de funcionários. O campo técnico legado de responsável recebe automaticamente o nome do setor nos novos lançamentos.
- KG: campos inteiros Quilogramas (kg) e Gramas (g), de 0 a 999 g. Ex.: 2 kg + 350 g = 2,350 kg; 0 kg + 500 g = meio quilo.
- +/− alteram 1 kg, 1 g ou 1 unidade. Quantidade deve ser positiva e UN deve ser inteira.
- Valor total continua solicitado para os registros e relatórios internos. Confirme setor, data, produtos, quantidades e valores antes de Confirmar lançamento. Voltar conserva o rascunho.
- Cancelamento exige justificativa e não pode alterar consumos protegidos por exportação.

## Exportação VR Master

Cozinha/Padaria: somente código interno e quantidade acumulada, nessa ordem. Ex.: `000125;2,35`. Peso sai em kg; unidades saem como inteiros.

Horti Fruti: código, quantidade, unidade fixa `1` e preço agregado em até quatro casas. Ex.: `000125;2,35;1;30`.

Separador, decimal, codificação, cabeçalho e fim de linha seguem o perfil configurado. A ordem dos quatro campos vale para Horti Fruti. Confira o layout efetivo de cada setor no VR Master; não houve homologação real nesta entrega.

O administrador seleciona um setor e filtros, confirma a reserva e depois confirma o salvamento do arquivo pelo histórico. Consumidos já reservados/exportados são ignorados. Reservar/autorizar exige internet para proteger itens entre aparelhos. Voltar no aviso não reserva/autoriza. Cancelar o seletor de destino depois da autorização mantém os itens protegidos.

Arquivos antigos mantêm seus bytes/colunas originais. Downloads repetidos do mesmo lote mantêm o arquivo. A confirmação da importação no VR é manual. Exportações feitas por outros sistemas não são conhecidas automaticamente. Não emite nota fiscal.

## Sincronização e recuperação

O primeiro acesso exige internet. Lançar/cancelar funciona offline com permissões previamente validadas. Sincronização é feita ao salvar, voltar ao app, manualmente e periodicamente enquanto aberto; não permanece ativa com o app encerrado. Um aparelho offline só conhece revogações/exportações recentes ao reconectar. Operações recusadas são preservadas para revisão.

Backups locais mantêm 14 cópias por identidade técnica; remotos mantêm 7 por identidade/aparelho. Funcionários têm somente os dois módulos; backups são automáticos. Administradores podem guardar/restaurar cópias autorizadas. Limites remotos: 20 MiB comprimidos e 64 MiB após expansão. Senha administrativa e tokens não estão no backup de dados.

**Não limpe dados ou armazenamento seguro para trocar setor ou contornar um erro.** Atualização sobre a instalação preserva banco/credencial. Desinstalação pode apagar banco, pendências e credencial. Identidades anônimas não têm login alternativo por e-mail/senha.

Se a credencial técnica for perdida, preserve o banco/backups e provisione um aparelho substituto. Os dados já sincronizados são recuperados pela nova conta técnica do setor ao sincronizar. Backups ligados à identidade antiga e operações nunca sincronizadas não são restaurados automaticamente em outra identidade: exigem recuperação administrativa controlada. Não descarte o aparelho antigo antes de resolver essas pendências.

A senha local protege o acesso pela interface, mas não criptografa SQLite nem substitui proteção do sistema operacional. Um aparelho é um vínculo lógico de instalação/credencial; não há atestação de hardware.

## Compilar e validar

Ambiente validado: Flutter 3.35.7/Dart 3.9.2 em Linux. Código atual: 1.6.1+9.

```text
flutter pub get
flutter analyze
flutter test
```

Em `tests_backend/`, execute `npm ci` e `npm test`. Resultado desta entrega: 88 testes Flutter, sete suítes SQL aprovados e análise estática sem ocorrências. Capturas são renderizadas por testes, não execução nativa Windows/Android físico. Não houve teste no Supabase da loja ou importação real no VR.

Windows: compile no Windows com Flutter e Visual Studio com Desenvolvimento para desktop com C++. Android: SDK Android e Java 17. A assinatura release permanente fica no kit privado entregue anteriormente; preserve-o separado do código. Não publique o kit ou suas senhas. Compile usando a mesma chave e código de versão 9 para atualizar.

O `intl` mantém a faixa `^0.20.2`; o ajuste CMake Linux do armazenamento seguro permanece incluído. No Ubuntu, use `flutter run -d linux`; `flutter run -d windows` exige Windows.

Veja `docs/ALTERACOES_1_6.md`, `docs/VALIDACAO.md` e a documentação histórica incluída no ZIP.
