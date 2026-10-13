# Provider: HashiCorp Vault (cofre remoto, KV v2)

Detalhes do cofre HashiCorp Vault (`https://vault.example.com`) usados pela skill `vault-factory`. Este arquivo é **referência** — a skill aponta para cá.

## Servidor e login

- Servidor: `https://vault.example.com`.
- O login é a função `vault-login`, definida no `~/.zshrc` do Samuel.
- O estado de login **não** é herdado por shells de subagentes. O classificador de permissões do harness também nega a leitura de `~/.zshrc` e o `vault token lookup` sem filtro.
- Portanto, **agentes não leem o vault**. O fluxo é um de dois:
  1. O Samuel roda no próprio shell, com `!`, um comando único cuja saída traz só nomes de chaves.
  2. O Samuel executa um script que lê os segredos direto para variáveis do processo, sem eco.

## Mount e convenção de paths

- Mount: `secret` (KV v2). `vault secrets list` mostra só `cubbyhole/`, `identity/`, `secret/` (v2) e `sys/`.
- **Erro comum:** tratar `prod` ou `hml` como mount. `vault kv get prod/app-b-prod` dá 403 "preflight capability check". O correto é `-mount=secret` seguido do path: `vault kv get -mount=secret prod/app-b-prod`.
- A policy (ACL) de KV v2 usa o caminho `secret/data/<path>`.

| Ambiente | Path (dentro do mount `secret`) | Exemplos |
|---|---|---|
| dev | `hml/<app>-dev` | `hml/app-a-dev`, `hml/app-b-dev` |
| hml | `hml/<app>-hml` | `hml/app-a-hml`, `hml/app-b-hml` |
| prod | `prod/<app>-prod` | `prod/app-a-prod`, `prod/app-b-prod` |

Dev e hml ficam sob `hml/`; produção fica sob `prod/`.

## Seguro x proibido (sessão de agente)

| Comando | Situação | Motivo |
|---|---|---|
| `vault kv list -mount=secret prod/` (e `hml/`) | Seguro | Lista só nomes de paths |
| `vault kv get -mount=secret -format=json <path> \| jq -c '.data.data \| keys'` | Seguro | Imprime só os nomes das chaves |
| `vault token capabilities secret/data/<path>` | Seguro | Mostra as permissões do token no path, sem valores |
| `vault kv get` sem filtro de valores | Proibido | Imprime os valores |
| `-field=<CHAVE>` com a saída exibida | Proibido | Imprime o valor da chave |
| `vault token lookup` sem `jq` | Proibido | Imprime o ID do token |

Em scripts que o **usuário** executa, `-field=<CHAVE>` atribuído direto a uma variável é aceitável, desde que haja:

- `set +x` e `umask 077` no início;
- nenhum `echo` ou `printf` do valor;
- `unset` e `trap` de limpeza ao sair.

```bash
set +x; umask 077
CHAVE="$(vault kv get -mount=secret -field=CHAVE prod/<app>-prod)" || exit 1
trap 'unset CHAVE' EXIT
```

Nunca gravar segredo em arquivo versionado, log ou histórico do shell.

## Escrita segura

- **Sempre confirmar com o Samuel o quê e onde** antes de escrever.
- Para adicionar chave a secret existente, use `vault kv patch`: ele mescla e mantém as outras chaves.
- **ARMADILHA CRÍTICA:** `vault kv put` em secret existente **substitui o secret inteiro** e apaga as outras chaves. Use `put` só para path novo, com todas as chaves de uma vez.
- Nunca passar o valor como argumento (`CHAVE=valor`): ele fica no histórico do shell e na lista de processos. Use stdin ou arquivo protegido:

```bash
# valor de uma linha, digitado sem eco no terminal do Samuel
read -rs VALOR && printf '%s' "$VALOR" | vault kv patch -mount=secret prod/<app>-prod CHAVE=- ; unset VALOR

# valor longo ou multilinha: arquivo com chmod 600, apagado ao terminar
vault kv patch -mount=secret prod/<app>-prod CHAVE=@/caminho/valor.txt
```

- Rollback: `vault kv rollback -mount=secret -version=<n> <path>` (cria nova versão com o conteúdo da versão `<n>`). Para ver as versões, use `vault kv metadata get -mount=secret <path>`, que não mostra valores.
- Depois de escrever, conferir os nomes das chaves com o comando seguro da tabela acima.

## Integração com os charts (ArgoCD)

- `templates/externalsecret.yaml` do chart usa o `ClusterSecretStore` `vault-backend` e `dataFrom` com `remoteKey: <hml|prod>/<app>-<env>`.
- O secret inteiro vira variáveis de ambiente do pod via `envFrom`. **O nome da chave no vault é o nome da variável** de ambiente.
- Variável sensível nova só precisa existir no vault; o template não muda.
- `refreshInterval`: 1h. O pod precisa reiniciar para pegar o valor novo.
- Valores não sensíveis (URLs, flags) vão no `configMap` do `values.yaml`. Só credenciais vão para o vault.

## Checklist de variável nova de integração

1. Sensível? Vault. Não sensível? `configMap` do `values.yaml`.
2. Usar o mesmo nome da variável do código ou do `appsettings`.
3. Dev e hml sob `hml/<app>-<env>`; prod sob `prod/<app>-prod`.
4. Vault: `vault kv patch` no path e restart do pod. ConfigMap: PR no chart.
5. Depois de escrever, conferir os nomes das chaves.

## Armadilhas

- Mount errado (`prod/...` usado como mount) dá 403 "preflight capability check". Use `-mount=secret`.
- `kv put` em secret existente apaga as outras chaves. Use `kv patch`.
- Agente não herda o login: não tentar ler o vault de dentro da sessão.
- O ExternalSecret atualiza a cada 1h, e o pod precisa reiniciar para usar o valor novo.
