# Consumo Interno 1.7.4+15 — tema para todos os setores

Causa: o seletor de tema estava dentro de Configurações, módulo exclusivo do administrador. Horti Fruti, Cozinha e Padaria não podiam acessá-lo.

Agora o botão Alterar tema, com ícone de aparência na barra superior, abre apenas o seletor Claro/Escuro/Automático. Reutiliza AppearanceCard e ThemeController existentes. A alteração aparece imediatamente e é salva como preferência do aparelho; funciona offline. Não concede acesso às configurações de conexão, produtos, relatórios ou administração. O seletor administrativo anterior continua disponível.

Atualize com git pull origin main, flutter pub get e recompile Android/Windows com a mesma configuração de conexão e chave de assinatura. Não exige migração Supabase. Não foi gerado novo APK/EXE.

Validação: revisão da visibilidade do botão para todos os setores, reutilização da persistência existente e análise sintática pelo formatador Dart. Não foram executados testes Flutter nem teste nativo em Android/Windows nesta alteração.
