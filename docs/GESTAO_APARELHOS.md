# Gestão de aparelhos por setor

## Uso

Abra Administração → Aparelhos. A lista em cache aparece primeiro e é atualizada pela nuvem ao abrir, se configurada. Use Atualizar para repetir a consulta. O filtro permite Todos os setores, Administração, Horti Fruti, Cozinha e Padaria, com contagem dos acessos exibidos.

Cada cartão identifica setor/papel, UUID da instalação, data de ativação e identidade técnica. Vínculos antigos sem instalação cadastrada continuam visíveis, com indicação de metadados indisponíveis. Não são exibidos e-mail, chave ou código de ativação.

Excluir acesso abre uma confirmação e remove o vínculo autorizado daquela identidade com a loja, usando a operação administrativa existente e sua auditoria. Produtos, consumos, backups, conta técnica Auth e cadastro histórico da ativação são preservados. Os demais aparelhos do setor continuam autorizados. A lista só mostra vínculos atualmente autorizados; a exclusão faz o aparelho sair dela após atualizar.

O servidor protege o último administrador. O botão de exclusão da própria máquina fica indisponível quando ela está identificada; use Sair ou trocar de setor para essa operação. Para autorizar novamente um aparelho excluído, gere um código novo.

## Offline e setores

Excluir exige conexão com a nuvem. Um aparelho offline só terá a revogação reconhecida ao conectar novamente: o aplicativo não pode apagar ou bloquear remotamente um computador desconectado. Preserve/sincronize suas pendências locais antes de revogar. A listagem em cache não indica presença online ou atividade em tempo real.

Os três setores são fixos. Excluir acesso remove uma autorização de aparelho; não exclui um setor nem seus registros.

## Instalação

Aplique `supabase/migrations/011_admin_device_listing.sql` após 010 e recompile Android/Windows. A migração redefine apenas a RPC de listagem administrativa e suas permissões. Não foi aplicada automaticamente ao seu Supabase. Nenhum novo APK/EXE foi gerado.

## Validação

Teste executado em PGlite com esquema completo e migrações 002–011: metadados, vínculo legado, separação entre lojas, rejeição de operador/anon, revogação individual, proteção do último administrador, preservação de Auth/backups, auditoria e reaplicação de 011. Fonte Flutter formatado; a interface não foi executada neste ambiente.
