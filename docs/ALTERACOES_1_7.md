# Consumo Interno 1.7.0+11

## Configuração incorporada ao aplicativo

Copie `config/connection.example.json` para `config/connection.local.json` e substitua os três valores por URL HTTPS, chave pública `sb_publishable_...` (ou JWT anon) e UUID da loja. Não use uma chave secreta ou service_role. O arquivo local não deve ser publicado no Git.

Compile no Windows:

```powershell
flutter pub get
flutter build windows --release --dart-define-from-file=config/connection.local.json
```

Android:

```bash
flutter pub get
flutter build apk --release --dart-define-from-file=config/connection.local.json
```

Os três campos aparecem preenchidos na primeira configuração. Continuam editáveis. Os valores salvos na instalação prevalecem sobre os padrões da compilação. Sem valores incorporados, a configuração manual e a leitura do QR continuam disponíveis. Esta entrega não contém as informações reais da loja, que ainda precisam ser fornecidas.

## Migração Supabase

Em loja com 008 já aplicada, execute somente `supabase/migrations/009_activation_and_scope_changes.sql`. Não reaplique schema.sql ou setup_sector_devices.sql. Loja nova precisa de schema.sql e 002 a 009 antes do setup. A migração não foi executada automaticamente na nuvem da loja.

009 permite administradores adicionais e troca de papel/setor autorizada por novo código. Cada identidade continua vinculada a uma instalação; códigos antigos de um escopo anterior são invalidados. O último administrador não pode mudar para um setor: ative outro administrador primeiro. A administração continua protegida por senha local em cada aparelho.

## QR Code de ativação

Em Administração → Aparelhos → Gerar código de ativação, escolha Administração ou um dos setores. O resultado mostra o código e o QR. É possível copiar a ativação ou salvar uma imagem PNG.

O QR inclui URL, chave pública, UUID da loja, setor sugerido e código de uso único. A autorização efetiva é validada no servidor. O código vale 24 horas. Compartilhe o QR somente com o responsável pelo aparelho autorizado.

No Android, toque em Ler QR Code e permita acesso à câmera. No Windows e no Android, Abrir imagem do QR Code lê um PNG/JPEG/WebP salvo; Colar ativação também aceita os dados copiados. Revise a loja e o acesso, confirme Preencher e depois Ativar aparelho. Não há ativação automática sem confirmação.

## Sair, trocar de setor ou alterar a loja

Use o botão Sair ou trocar de setor na barra superior. Confirme a saída. O aplicativo espera os lançamentos em andamento, sincroniza, recusa pendências/recibos ainda não enviados e grava um backup local obrigatório, mesmo se o backup automático estiver desativado. Se a sincronização ou o backup falhar, a saída não é concluída.

Depois, leia o QR ou digite um código novo do setor desejado. Pode alterar URL, chave e loja na mesma tela. A troca exige internet. A credencial técnica anterior permanece guardada por projeto/loja no armazenamento seguro; ela não é enviada ao novo projeto. Os dados do escopo anterior são retirados do cache ativo somente na transição, após a cópia local. As operações já sincronizadas continuam na nuvem. Rascunhos ainda não lançados são descartados, conforme o aviso.

Na mesma loja, um código novo autoriza a alteração da identidade técnica para o novo setor/papel e invalida o código anterior. Para voltar a um setor antigo, solicite outro código. Para apenas retornar ao mesmo acesso sem trocá-lo, o código já usado pela mesma identidade e instalação continua aceito. Não selecione setores livremente: o servidor deriva o setor do código autorizado.

Para substituir ou revogar uma máquina específica, use Editar acesso na lista de aparelhos. Não use substituição por setor. A geração de códigos adicionais não desconecta as outras máquinas. Se houver vários administradores, a recuperação deve identificar a máquina desejada; a antiga substituição administrativa global é recusada.

## Verificação desta alteração

- Nove suítes SQL passaram, incluindo várias máquinas, administradores adicionais, troca por código novo, revogação, proteção do último administrador e exportação sem reexportação.
- Teste Dart independente passou para serialização/validação da ativação, rejeição de chave privilegiada e geração/leitura de QR PNG com rotação.
- Análise estática de lib e test feita com o analisador Dart.
- Foram adicionados testes Flutter de QR, isolamento de conexão e proteção de pendências. A execução da suíte Flutter local foi bloqueada pela revisão automática porque o comando tentou acessar um endpoint de metadados do ambiente. Não foi feita validação nativa da câmera, nem gerado APK/EXE novo nesta alteração.
