# Alterações — 1.6.0+8

O uso diário identifica o setor e o aparelho, sem pedir nome de funcionário, e-mail ou login. A autenticação técnica continua necessária para aplicar RLS e sincronizar com segurança; cada aparelho cria automaticamente uma identidade Supabase Auth sem e-mail.

## Fluxo

1. O responsável pelo projeto habilita **Allow anonymous sign-ins**, aplica a migração 007 e gera os códigos iniciais pelo SQL Editor.
2. Na instalação, o administrador informa URL, chave pública, UUID da loja e código de ativação. O código determina papel/setor; não há escolha livre de papel no aparelho.
3. O aparelho do setor abre diretamente Lançar consumo, inclusive offline, com somente Lançar/Cancelar. O setor é fixo e os produtos continuam filtrados.
4. O aparelho administrativo define senha própria (8–128 caracteres). Reabrir, voltar do segundo plano ou Bloquear administração exige desbloqueio; o desbloqueio funciona offline. A senha é derivada com PBKDF2-HMAC-SHA256, 120 mil iterações e salt aleatório, e armazenada no armazenamento seguro do sistema.
5. Administração → Aparelhos gera códigos para setores, com opção explícita de substituir aparelho e justificativa. Administrador inicial/recuperação administrativa são provisionados somente pelo responsável no SQL Editor.

## Regras

- Código de 32 caracteres hexadecimais, validade de 24 horas e hash no banco. O código completo aparece somente ao gerar e não entra na auditoria.
- Um aparelho ativado por setor/loja. Papel e setor não podem ser alterados pelos APIs antigos de administração.
- Reenvio de uma ativação aceita somente a mesma identidade técnica e o mesmo ID de instalação; não cria outro cadastro quando a resposta se perde.
- Código antigo não restaura acesso revogado nem apaga senha administrativa já definida. Código administrativo novo permite recuperar a senha no aparelho vinculado.
- Identidade técnica/token ficam no armazenamento seguro. Não há botão para descartar a credencial anônima: bloquear a administração não encerra a credencial de sincronização.
- Novos consumos preenchem o campo técnico legado `operator` com o nome do setor. O formulário não pede responsável. Dados históricos não são reescritos.
- Lançamentos, precisão KG/UN, confirmação, formatos de exportação da 1.5, proteção contra reexportação e backups continuam preservados.

## Atualização e recuperação

Aplicar `007_sector_devices.sql` após 006 e recompilar. Atualização sobre a instalação mantém banco e credencial; não apague armazenamento seguro. Sessões antigas continuam renovando seus tokens sem pedir e-mail na nova interface. Administradores vinculados também passam a definir/desbloquear a senha local.

Para migrar um setor existente, preserve sua credencial e use o código no mesmo aparelho. Se houver outros vínculos antigos do mesmo setor, revogue-os antes; o servidor recusa ativação que permitiria dois vínculos. Substituição revoga o vínculo anterior; aparelhos offline reconhecem a revogação na próxima conexão.

Se o token anônimo for perdido por desinstalação/limpeza, não é possível entrar novamente na mesma identidade com e-mail/senha. Preserve os arquivos e provisione um aparelho substituto. Dados já sincronizados são recuperados da loja/setor pela sincronização. Backups ligados à identidade anterior e operações nunca sincronizadas exigem recuperação administrativa controlada; não são importados automaticamente em outra identidade.

O limite de um aparelho é um vínculo lógico de instalação/credencial, sem atestação criptográfica do hardware. A senha local não substitui proteção do sistema operacional nem criptografa o banco SQLite. Backups não contêm a senha nem o token.

## Validação

88 testes Flutter, sete suítes SQL e análise estática sem ocorrências. Novos casos: identidade sem e-mail, repetição após resposta perdida, credencial perdida sem criação de outra conta, senha persistida/reabertura/código antigo, vetor PBKDF2 independente, lançamento offline por setor e bloqueio administrativo.

Sem execução em aparelho físico, Windows nativo, Supabase real ou VR nesta entrega. Nenhum novo APK/EXE foi compilado e nenhum projeto Supabase da loja foi alterado. Veja o guia e a validação atual.
