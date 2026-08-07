---
name: keycloak-api
description: Consulta e sincroniza a Admin REST API de instâncias Keycloak (token, roles de realm/client, groups, e espelhamento de roles/groups entre dois ambientes como dev→stg) sem que o client_secret seja digitado em texto puro na conversa. Credenciais ficam num arquivo local protegido; scripts nunca imprimem secret ou token. Use quando o usuário pedir para consultar, comparar ou espelhar (replicar) roles/clients/groups entre ambientes Keycloak.
---

# Keycloak API

Esta skill encapsula chamadas comuns à Admin REST API do Keycloak, mantendo `client_secret` fora do contexto da conversa e do histórico de chat.

## Princípio de segurança

- **Nunca peça ao usuário para colar o `client_secret` na mensagem de chat.** Se ele fizer isso mesmo assim, use normalmente mas avise que o ideal é rotacionar a credencial depois, pois ela ficou registrada no histórico da conversa.
- As credenciais vivem em `~/.claude/secrets/keycloak/<alias>.env`, com permissão `600`, e nunca são lidas com `cat`/`Read` por Claude — só são `source`adas dentro do processo do próprio script.
- Os scripts em `scripts/` nunca fazem `echo`/`print` do `client_secret` nem do `access_token`. A resposta de `/admin/realms/{realm}/clients` do Keycloak inclui o campo `secret` em texto puro — por isso `kc-list-clients.sh` e `kc-client-roles.sh` filtram esse campo antes de qualquer saída chegar ao contexto do modelo.
- `scripts/kc.sh` é um CLI único (`kc <subcomando> ...`) que só delega para os scripts individuais via `exec` — nenhuma lógica nova, nenhum novo caminho de exposição de secret.

## Primeiro uso (nenhuma credencial salva ainda)

Se `~/.claude/secrets/keycloak/<alias>.env` não existir para o alias desejado, peça ao usuário para rodar o comando de setup — **nunca peça a secret diretamente na mensagem**. Duas opções, em ordem de preferência:

1. **Mais seguro:** o usuário abre um terminal à parte (fora do Claude Code) e roda:
   ```
   kc setup-credentials
   ```
   (ou, se ainda não rodou `init.sh`: `~/.claude/skills/keycloak-api/scripts/kc.sh setup-credentials`)
2. **Aceitável:** o usuário roda o mesmo comando dentro do Claude Code usando o prefixo `!`. Como o script usa `read -s` para a secret e nunca a imprime, o valor não aparece na conversa — apenas a confirmação de que foi salva.

O script pede: alias (nome curto para identificar essa credencial, ex: `realm-dev-meu-app`), base URL, realm, client ID e client secret (oculto).

Depois disso, use o alias escolhido nos comandos abaixo.

## Comandos disponíveis

Interface única: `kc <subcomando> [args...]` (ver `kc --help`). Por baixo, cada subcomando delega
via `exec` para o script individual correspondente em `scripts/` — só o `kc` é exposto como
comando de shell (ver seção de exposição abaixo); os `kc-*.sh` continuam existindo como
implementação interna, chamados pelo wrapper ou entre si (ex: `kc-mirror-client-roles.sh` chama
`kc-client-roles.sh` e `kc-create-client-role.sh` diretamente por caminho).

Todos os subcomandos recebem o `<alias>` salvo no setup.

### Consulta

- `kc token <alias>` — obtém um access_token (uso interno, imprime só o token; evite mostrar isso diretamente ao usuário).
- `kc realm-roles <alias>` — lista as roles de nível de realm (JSON).
- `kc list-clients <alias>` — lista os clients do realm (id interno, clientId, name, enabled — sem secret).
- `kc client-roles <alias> <clientId>` — lista as roles de um client pelo nome (ex: `meu-app`). Resolve o id interno sem expor o corpo bruto de `/clients` (que contém a secret).
- `kc list-groups <alias>` — lista os groups do realm (árvore completa).
- `kc group-detail <alias> <groupId>` — detalha um group: subgrupos, membros, role mappings (realm + client).

### Criação pontual

- `kc create-client-role <alias> <clientId> <roleName> [descricao]` — cria uma role num client. Idempotente (reporta "JÁ EXISTE" em vez de duplicar).

### Espelhamento entre ambientes (uso recorrente — preferir estes em vez de recompor a lógica manualmente)

Fluxo típico do usuário: comparar/replicar roles e groups de um client entre dois ambientes (ex: dev → stg). Os dois subcomandos abaixo são **idempotentes** — podem ser rodados de novo sem duplicar nada, e servem tanto para aplicar quanto para conferir paridade (rodar de novo e ver "já em paridade" = confirmação).

- `kc mirror-client-roles <sourceAlias> <targetAlias> <clientIdName>` — cria no client de destino as roles (nome + descrição) que existem na origem e faltam no destino. Assume mesmo `clientId` nos dois ambientes.
- `kc mirror-group-roles <sourceAlias> <targetAlias> <groupPath> <clientIdName> [--recursive]` — espelha os **client-role-mappings de um group** da origem para o destino. Cria o group no destino se não existir (inclusive hierarquia intermediária). Com `--recursive`, aplica também a todos os subgrupos (por nome) encontrados na origem — cobre uma árvore inteira (ex: `/MeuApp` + todos os filhos) numa única chamada.

Ordem recomendada ao espelhar um client completo entre ambientes: primeiro `kc mirror-client-roles` (garante que as roles existem no destino), depois `kc mirror-group-roles ... --recursive` (garante que os groups apontam pra elas). Rodar `kc mirror-client-roles` antes é obrigatório — `kc mirror-group-roles` só consegue mapear roles que já existem no client de destino.

Exemplos:
```
kc client-roles realm-dev-meu-app meu-app
kc mirror-client-roles realm-dev-meu-app realm-stg-meu-app meu-app
kc mirror-group-roles realm-dev-meu-app realm-stg-meu-app "/MeuApp" meu-app --recursive
```

Antes do `init.sh` (ou se preferir caminho completo): `~/.claude/skills/keycloak-api/scripts/kc.sh <subcomando> ...`.

## Disponibilizar o comando fora da skill

`scripts/init.sh` symlinka em `~/.local/bin` (já no `PATH`) e adiciona alias no `~/.zshrc` **só do
`kc`** — os scripts individuais (`kc-*.sh`) não viram comandos de shell, ficam só como
implementação interna do wrapper (controlado por `scripts/.expose`, que lista apenas `kc`).
Idempotente, não mexe em blocos de outras skills:

```bash
~/.claude/skills/keycloak-api/scripts/init.sh
source ~/.zshrc   # ou abrir um novo terminal
```

Depois disso, `kc <subcomando> ...` funciona em qualquer diretório/shell (ex: `kc token realm-dev-meu-app`).

## Ao apresentar resultados ao usuário

- Formate roles como tabela ou lista — não é necessário mostrar o JSON bruto.
- Nunca inclua o `access_token` ou `client_secret` na resposta final ao usuário.
- Se múltiplos aliases existirem, liste os arquivos em `~/.claude/secrets/keycloak/*.env` (só os nomes, não o conteúdo) para o usuário escolher, caso não tenha especificado qual usar.
