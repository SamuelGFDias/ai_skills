---
name: keycloak-api
description: Consulta e sincroniza a Admin REST API de instâncias Keycloak (token, roles de realm/client, groups, e espelhamento de roles/groups entre dois ambientes como dev→stg) sem que o client_secret seja digitado em texto puro na conversa. Realms e credenciais (client ou user) são cadastrados separadamente — um client/user referencia um realm por alias. Credenciais ficam num arquivo local protegido; scripts nunca imprimem secret ou token. Use quando o usuário pedir para consultar, comparar ou espelhar (replicar) roles/clients/groups entre ambientes Keycloak, ou para cadastrar/editar realms, clients ou usuários dessa skill.
---

# Keycloak API

Esta skill encapsula chamadas comuns à Admin REST API do Keycloak, mantendo `client_secret`/senha fora do contexto da conversa e do histórico de chat.

## Modelo de cadastro: realm, client e user são separados

Diferente de um modelo antigo (um "alias" só, com base URL + realm + client tudo junto),
aqui **realm** e **credencial** são cadastrados independentemente:

- **Realm** (`kc setup-realm`) — só base URL + nome técnico do realm. Pode ser salvo:
  - **local**: `~/.claude/secrets/keycloak/realms/<realmAlias>.env` — só nesta máquina.
  - Resolução: o realm é lido do arquivo local.
- **Client** (`kc setup-client`) — client_id + client_secret, associado a um realm já
  cadastrado (o script mostra um menu pra escolher, não precisa redigitar base URL/realm).
  Autentica via `grant_type=client_credentials` (service account do client).
- **User** (`kc setup-user`) — username + senha, também associado a um realm por menu.
  Autentica via `grant_type=password`, usando um client público (padrão `admin-cli`).
  Use para operações **fora do escopo de um client** — quando não há service account
  habilitado e a chamada precisa ser feita como um usuário humano/admin do realm.

Todo comando de consulta/ação recebe um **`<credAlias>`** — o alias de um client OU de um
user cadastrado (ambos resolvem para um token do mesmo jeito; o alias deve ser único entre os
dois, os scripts de setup avisam se colidir).

## Princípio de segurança

- **Nunca peça ao usuário para colar `client_secret` ou senha na mensagem de chat.** Se ele
  fizer isso mesmo assim, use normalmente mas avise que o ideal é rotacionar a credencial
  depois, pois ela ficou registrada no histórico da conversa.
- Secrets de client/user vivem em `~/.claude/secrets/keycloak/{clients,users}/<alias>.env`,
  permissão `600`, e **nunca** são lidos com `cat`/`Read` por Claude — só são `source`ados
  dentro do processo do próprio script. Realms (sem secret) vivem em
  `~/.claude/secrets/keycloak/realms/` (local).
- Ao cadastrar/editar (`kc setup-client`, `kc setup-user`), a secret/senha é lida caractere a
  caractere e **cada caractere digitado ou colado vira um `*` na tela na hora** — dá pra
  conferir visualmente que colou (e não colou em dobro) antes de confirmar. No fim, o script
  também mostra uma barra de `*` do tamanho salvo + contagem de caracteres, pra conferência.
  Nunca ecoa o valor real em texto puro.
- Os scripts em `scripts/` nunca fazem `echo`/`print` do `client_secret`, senha, nem do
  `access_token`. A resposta de `/admin/realms/{realm}/clients` do Keycloak inclui o campo
  `secret` em texto puro — por isso `kc-list-clients.sh` e `kc-client-roles.sh` filtram esse
  campo antes de qualquer saída chegar ao contexto do modelo.
- `scripts/kc.sh` é um CLI único (`kc <subcomando> ...`) que só delega para os scripts
  individuais via `exec` — nenhuma lógica nova, nenhum novo caminho de exposição de secret.
- `scripts/lib-env.sh` centraliza a resolução de credencial/realm (`load_credential_env`,
  `resolve_realm_env_file`) — é sourced por todo `kc-*.sh` e `setup-*.sh`, nunca executado
  diretamente.
- Chamadas HTTP passam por `api_request` (também em `lib-env.sh`): checa o status HTTP e, em
  erro, imprime "Erro HTTP `<status>` em `<method>` `<url>`" + a mensagem do Keycloak — nunca
  o corpo bruto. Isso evita que um 401/403 apareça pro usuário como um traceback de
  `JSONDecodeError` do Python (curl -f descarta o corpo em erro, e sem esse wrapper o parser
  json recebia stdin vazio e quebrava com uma mensagem sem sentido pro usuário).

## Primeiro uso (nenhum realm/credencial cadastrado ainda)

Antes de qualquer coisa, confira `kc list-realms`.

Se o realm desejado não estiver em `kc list-realms`, ou se não houver `client`/`user`
cadastrado ainda para ele (confira em `kc list-clients-config` / `kc list-users-config`),
peça ao usuário para rodar o setup correspondente — **nunca peça secret/senha diretamente
na mensagem**. Duas opções, em ordem de preferência:

1. **Mais seguro:** o usuário abre um terminal à parte (fora do Claude Code) e roda:
   ```
   kc setup-realm      # só se o realm ainda não existir em `kc list-realms`
   kc setup-client      # ou: kc setup-user
   ```
   (ou, se ainda não rodou `init.sh`: `~/.claude/skills/keycloak-api/scripts/kc.sh setup-client`)
2. **Aceitável:** o usuário roda o mesmo comando dentro do Claude Code usando o prefixo `!`.
   Os prompts são interativos (`select` para escolher o realm, leitura mascarada pra
   secret/senha) — funcionam normalmente com `!`, e o valor real nunca aparece na conversa,
   só os `*` de conferência e a confirmação final.

`kc setup-client`/`kc setup-user` mostram um menu com os realms disponíveis (equipe + locais)
pra escolher — não pedem para redigitar base URL/realm.

Depois disso, use o alias de client/user escolhido (`<credAlias>`) nos comandos abaixo.

## Comandos disponíveis

Interface única: `kc <subcomando> [args...]` (ver `kc --help`). Por baixo, cada subcomando
delega via `exec` para o script individual correspondente em `scripts/` — só o `kc` é exposto
como comando de shell (ver seção de exposição abaixo); os `kc-*.sh`/`setup-*.sh` continuam
existindo como implementação interna.

### Cadastro

- `kc setup-realm` — cadastra/edita um realm. Pergunta onde salvar: **local** (só esta
  máquina) ou **equipe** (versionado no repo da skill — não commita/pusha sozinho, só grava
  o arquivo; avise o usuário que ainda precisa dar `git add/commit/push` em
  `~/.config/ai/skills` para o time receber).
- `kc setup-client` — cadastra/edita um client (escolhe o realm num menu). Secret mascarada
  com `*` em tempo real.
- `kc setup-user` — cadastra/edita uma credencial de usuário (username/senha, escolhe o realm
  num menu). Senha mascarada com `*` em tempo real. Client de login padrão: `admin-cli`. Ao
  editar um alias existente, se o realm selecionado no menu for diferente do atual, mostra
  `ATENÇÃO: realm será alterado de X para Y` — o realm sempre é sobrescrito pelo escolhido no
  menu (não é preservado por Enter como os outros campos).
- `kc delete-client <alias>` / `kc delete-user <alias>` — remove o cadastro local de um
  client/usuário (arquivo em `~/.claude/secrets/keycloak/{clients,users}/`). Pede confirmação
  `[s/N]` — em uso não-interativo (ex: rodado por Claude via Bash tool), só remove se receber
  `s` na entrada (`echo s | kc delete-user <alias>`), e só faça isso quando o usuário pedir
  explicitamente a remoção desse alias. Nunca afeta o client/usuário no Keycloak em si, só o
  cadastro local desta skill.

### Consulta de cadastro local

- `kc list-realms` — lista os realms disponíveis (local + equipe), com a coluna ORIGEM.
- `kc list-clients-config` — lista os clients cadastrados (alias, realm, client id — sem secret).
- `kc list-users-config` — lista os usuários cadastrados (alias, realm, client id, username — sem senha).

Use estes para descobrir o que já existe antes de pedir ao usuário para rodar um setup.

### Consulta na API do Keycloak

Todos aceitam qualquer `<credAlias>` — de um client ou de um user cadastrado, tanto faz.

- `kc token <credAlias>` — obtém um access_token (uso interno, imprime só o token; evite
  mostrar isso diretamente ao usuário).
- `kc realm-roles <credAlias> [realmDestino]` — lista as roles de nível de realm (JSON).
- `kc list-clients <credAlias> [realmDestino]` — lista os clients do realm (id interno,
  clientId, name, enabled — sem secret). Não confundir com `kc list-clients-config`: este
  consulta a API do Keycloak ao vivo; aquele lista o cadastro local desta skill.
- `kc client-roles <credAlias> <clientId> [realmDestino]` — lista as roles de um client pelo
  nome (ex: `meu-app`). Resolve o id interno sem expor o corpo bruto de `/clients` (que contém a
  secret).
- `kc list-groups <credAlias> [realmDestino]` — lista os groups do realm (árvore completa).
- `kc group-detail <credAlias> <groupId> [realmDestino]` — detalha um group: subgrupos,
  membros, role mappings (realm + client).

`realmDestino` (opcional, nesses 5 comandos): consulta outro realm da **mesma instância**
Keycloak da credencial, usando o token dela — cobre o padrão de admin do realm `master`, que
autentica no `master` mas no Keycloak pode gerenciar qualquer outro realm da mesma instância
(diferente de ser admin dentro do realm de destino em si). Sem `realmDestino`, consulta o
próprio realm da credencial (comportamento de sempre). Exemplo explícito: uma credencial de
usuário autenticada no realm `master` consultando os clients do realm `realm-dev` na mesma
instância: `kc list-clients realm-dev-master realm-dev`.

**Modo automático — passar um REALM em vez de uma credencial:** nesses mesmos 5 comandos, o
1º argumento também aceita o alias de um **realm cadastrado** (em vez de um credAlias). Nesse
caso a skill resolve sozinha uma credencial de admin do `master` da mesma instância (mesma
base URL) e usa pra consultar o realm informado — sem precisar saber de cor o alias da
credencial de master:
```
kc list-clients realm-dev
kc client-roles realm-dev meu-app
```
Comportamento (função `resolve_target_credential` em `lib-env.sh`):
- 0 credenciais de master cadastradas para essa instância → erro pedindo `kc setup-realm`
  (realm técnico `master`, mesma base URL) + `kc setup-user`.
- 1 candidata (ou já houver um default salvo pra essa base URL) → usa direto, sem perguntar.
- 2+ candidatas sem default → menu interativo (`select`) pra escolher, depois pergunta `[s/N]`
  se quer salvar como padrão pra essa instância (arquivo em
  `~/.claude/secrets/keycloak/master-defaults/`). Como usa `select`/`read` interativos, rodar
  com o prefixo `!` se for você (usuário) a decidir; se for Claude decidindo em nome do
  usuário, isso não deve acontecer sem confirmação dele antes.
- Sempre imprime em stderr qual credencial foi usada (`Usando credencial de master 'X'...`) —
  nunca oculto, pra não confundir com escolha errada depois.

**Escopos do Keycloak — por que um 403 não é sempre bug:** um **client** (service account,
grant_type=client_credentials) só enxerga o que as roles atribuídas ao service account dele
permitirem — sem role de `realm-management` (`view-clients`, `view-realm`, `realm-admin`...),
as chamadas à Admin REST API voltam 403 mesmo com o client_secret certo. Um **usuário**
(grant_type=password) tem o mesmo problema a menos que seja admin do `master` (aí gerencia
qualquer realm da instância, ver modo automático acima) ou tenha essas roles atribuídas
diretamente nele. `api_request` (em `lib-env.sh`) já reconhece isso: num 403, olha
`KEYCLOAK_AUTH_TYPE` da credencial em uso e imprime uma dica específica (qual role pedir, ou
sugestão de usar o modo automático com um usuário master) em vez de só "Forbidden".

### Criação pontual

- `kc create-client-role <credAlias> <clientId> <roleName> [descricao]` — cria uma role num
  client. Idempotente (reporta "JÁ EXISTE" em vez de duplicar).

### Espelhamento entre ambientes (uso recorrente — preferir estes em vez de recompor a lógica manualmente)

Fluxo típico do usuário: comparar/replicar roles e groups de um client entre dois ambientes
(ex: dev → stg). Os dois subcomandos abaixo são **idempotentes** — podem ser rodados de novo
sem duplicar nada, e servem tanto para aplicar quanto para conferir paridade (rodar de novo e
ver "já em paridade" = confirmação).

- `kc mirror-client-roles <sourceCredAlias> <targetCredAlias> <clientIdName>` — cria no
  client de destino as roles (nome + descrição) que existem na origem e faltam no destino.
  Assume mesmo `clientId` nos dois ambientes.
- `kc mirror-group-roles <sourceCredAlias> <targetCredAlias> <groupPath> <clientIdName> [--recursive]`
  — espelha os **client-role-mappings de um group** da origem para o destino. Cria o group no
  destino se não existir (inclusive hierarquia intermediária). Com `--recursive`, aplica
  também a todos os subgrupos (por nome) encontrados na origem — cobre uma árvore inteira
  (ex: `/MeuApp` + todos os filhos) numa única chamada.

Ordem recomendada ao espelhar um client completo entre ambientes: primeiro
`kc mirror-client-roles` (garante que as roles existem no destino), depois
`kc mirror-group-roles ... --recursive` (garante que os groups apontam pra elas). Rodar
`kc mirror-client-roles` antes é obrigatório — `kc mirror-group-roles` só consegue mapear
roles que já existem no client de destino.

Exemplos:
```
kc client-roles realm-dev-meu-app meu-app
kc mirror-client-roles realm-dev-meu-app realm-stg-meu-app meu-app
kc mirror-group-roles realm-dev-meu-app realm-stg-meu-app "/MeuApp" meu-app --recursive
```

Antes do `init.sh` (ou se preferir caminho completo): `~/.claude/skills/keycloak-api/scripts/kc.sh <subcomando> ...`.

## Disponibilizar o comando fora da skill

`scripts/init.sh` symlinka em `~/.local/bin` (já no `PATH`) e adiciona alias no `~/.zshrc` **só do
`kc`** — os scripts individuais (`kc-*.sh`, `setup-*.sh`, `lib-env.sh`) não viram comandos de
shell, ficam só como implementação interna do wrapper (controlado por `scripts/.expose`, que
lista apenas `kc`). Idempotente, não mexe em blocos de outras skills:

```bash
~/.claude/skills/keycloak-api/scripts/init.sh
source ~/.zshrc   # ou abrir um novo terminal
```

Depois disso, `kc <subcomando> ...` funciona em qualquer diretório/shell (ex: `kc token realm-dev-meu-app`).

## Ao apresentar resultados ao usuário

- Formate roles como tabela ou lista — não é necessário mostrar o JSON bruto.
- Nunca inclua o `access_token`, `client_secret` ou senha na resposta final ao usuário.
- Se o `<credAlias>` não tiver sido especificado pelo usuário, rode `kc list-clients-config`
  e/ou `kc list-users-config` para mostrar as opções (alias, realm, client id/username —
  nunca secret/senha). Se nem o realm estiver claro, rode `kc list-realms` primeiro.
