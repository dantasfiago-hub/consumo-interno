# Validação — 1.4.0+5

Verificada em 4 de outubro de 2026, com Flutter 3.35.7 e Dart 3.9.2 em Linux.

## Resultados

- `flutter analyze`: sem ocorrências.
- **59 testes Flutter aprovados**: domínio/precisão, armazenamento, permissões dos três setores, telas em 390 e 1280 pixels, temas, exportação, integridade/restauração, retenção de 14 cópias, backups simultâneos, limite de descompressão, fotos deduplicadas e retentativas.
- HTTP controlado com **duas instalações e bancos locais independentes**: PC reserva o consumo; celular cancela offline, recebe recusa, mantém a operação e envia a pendência central. A revisão adota o consumo protegido, arquiva tentativa/justificativa local e não reenviou o cancelamento. A mesma foto foi baixada uma vez por instalação.
- **Quatro suítes PostgreSQL/PGlite aprovadas**: operações/exportação legadas/v2; setores/v3; administração/auditoria/mídia/backups/v4; migração de loja existente e solicitações sobrepostas de exportação.
- SQL/RLS verifica isolamento por loja/setor, último administrador, checksum de imagens, impossibilidade de sobrescrever consumos exportados na revisão, revisão idempotente, aplicação controlada de lançamento novo e retenção de 7 backups por conta/dispositivo. Mudança de setor retira acesso às antigas fotos, pendências e cópias do funcionário.
- Migração de dados preenchidos preserva versões, foto e idempotência anteriores, incorporando auditoria retroativa. Duas solicitações para o mesmo item resultam em uma reserva ativa.
- Ícones PNG/ICO e tela de exportação conferidos visualmente. Capturas em `screenshots/` atualizadas pelo renderizador Flutter com dados fictícios.

## Binários e distribuição

APK **release Android ARM64**, versão **1.4.0**, código **5**, API mínima **24** (Android 7.0+). Manifesto, bibliotecas nativas, ícone empacotado e assinatura verificados. O nome do arquivo mantém o das entregas anteriores, mas a assinatura é release.

Certificado SHA-256: `d1378d587ce4a0541099c3d25e725866c32e2490c93dd33b2eed3d3692aae9f0`.

A chave permanente está no kit privado `consumo_interno_assinatura.zip`, separado do código. A assinatura difere dos APKs de teste anteriores. Sincronize todos os dispositivos e preserve backups antes de uma eventual desinstalação. Próximas atualizações devem usar esta chave e código de versão maior. Credenciais não estão no ZIP de código nem devem ir ao Git.

Código-fonte e ícone Windows incluídos; não há EXE fornecido. Compilação Windows exige Windows, Flutter e Visual Studio C++.

## Evidências e limites

Não houve execução em Android físico nem execução nativa Windows. As duas instalações foram simuladas por HTTP/bancos independentes. PGlite serializa comandos; o teste de solicitações sobrepostas verifica a regra SQL e não mede concorrência em conexões reais PostgreSQL.

Nenhum projeto Supabase da loja foi alterado. Aplique 004 após as migrações anteriores antes de distribuir esta versão. Contas são criadas no Authentication; o novo painel administra seus vínculos. Dados/permissões da loja exigem configuração.

Não houve importação real no VR Master. Confira o perfil com o Layout Coletor da instalação; a confirmação de importação permanece manual. Registros exportados por outros aplicativos não são conhecidos por este sistema.

Lançar/cancelar funciona offline com permissões previamente validadas. Reservar/exportar exige conexão para proteger itens entre dispositivos. Um aparelho offline desconhece exportações ou revogações recentes; operações incompatíveis são recusadas na sincronização e mantidas para revisão. O aplicativo não sincroniza continuamente quando encerrado.

Backups remotos iniciam nesta versão e dependem de sincronização/serviço disponível. Cópias locais no diretório do app podem ser apagadas pela desinstalação; copie-as para outro local. Limites remotos: 20 MB comprimidos e 64 MB após expansão. Erros ficam visíveis sem apagar o banco. Recuperação exige instalação vazia e conta/escopo autorizado.

Lotes antigos continuam protegendo seus itens. Somente reservas canceladas antes da autorização de salvamento liberam itens. A revisão administrativa não remove essa proteção.
