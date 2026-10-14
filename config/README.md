# Configuração local de conexão

O nome recomendado é `config/connection.local.json`. O arquivo
`config/connection.json` também é aceito ao informar seu caminho no comando de
compilação. Ambos estão no `.gitignore` e não devem ser adicionados com `git add -f`.

Formato de exemplo, sem valores reais:

```json
{
  "DEFAULT_SUPABASE_URL": "https://SEU-PROJETO.supabase.co",
  "DEFAULT_SUPABASE_PUBLIC_KEY": "sb_publishable_SUA_CHAVE_PUBLICA",
  "DEFAULT_STORE_ID": "UUID_DA_LOJA"
}
```

Compile com o caminho escolhido:

```sh
flutter build apk --dart-define-from-file=config/connection.local.json
```

Use somente a chave pública. Credenciais `service_role` e chaves secretas não
podem ser incorporadas ao aplicativo. Os campos de conexão continuam editáveis
na ativação.
