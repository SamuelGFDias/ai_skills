#!/usr/bin/env bash
# lib-env.sh — funções compartilhadas pelos scripts kc-*.sh e setup-*.sh.
# Sempre sourced (nunca executado diretamente). Não imprime secret em nenhuma função.
#
# Modelo de armazenamento: realm e credencial (client ou user) são cadastrados separadamente.
#   ~/.claude/secrets/keycloak/realms/<realmAlias>.env   -> realms pessoais/locais (fora do git)
#   keycloak-api/realms/<realmAlias>.env                 -> realms da equipe (versionado no repo
#                                                            da skill, só base URL + nome — sem
#                                                            secret, seguro de commitar)
#   ~/.claude/secrets/keycloak/clients/<alias>.env       -> KEYCLOAK_REALM_ALIAS, KEYCLOAK_CLIENT_ID, KEYCLOAK_CLIENT_SECRET
#   ~/.claude/secrets/keycloak/users/<alias>.env         -> KEYCLOAK_REALM_ALIAS, KEYCLOAK_CLIENT_ID, KEYCLOAK_USERNAME, KEYCLOAK_PASSWORD
# Uma credencial (client ou user) aponta para um realm pelo alias — evita repetir base
# URL/realm a cada credencial cadastrada no mesmo ambiente. Resolução de realm: local do
# usuário tem prioridade sobre o compartilhado da equipe (permite override pessoal de um
# realm que também existe no arquivo versionado, ex: apontar realm-dev pra outra URL só
# na sua máquina, sem afetar o resto da equipe).
#
# client = autentica via grant_type=client_credentials (service account do client).
# user   = autentica via grant_type=password, usando um client público (ex: admin-cli) +
#          usuário/senha — necessário para operações fora do escopo de um client (ex: admin
#          do realm via usuário humano, quando não há service account habilitado).
# O alias de uma credencial deve ser único entre clients/ e users/ juntos — setup-client e
# setup-user avisam e abortam se o alias já existir do outro lado, para não colidir.

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_REALMS_DIR="$LIB_DIR/../realms"

SECRETS_ROOT="$HOME/.claude/secrets/keycloak"
REALMS_DIR="$SECRETS_ROOT/realms"
CLIENTS_DIR="$SECRETS_ROOT/clients"
USERS_DIR="$SECRETS_ROOT/users"

# Caminho do .env de um realm, preferindo o cadastro local ao compartilhado da equipe.
# Imprime vazio (sem erro) se não existir em nenhum dos dois.
resolve_realm_env_file() {
  local alias="$1"
  if [ -f "$REALMS_DIR/${alias}.env" ]; then
    printf '%s' "$REALMS_DIR/${alias}.env"
  elif [ -f "$TEAM_REALMS_DIR/${alias}.env" ]; then
    printf '%s' "$TEAM_REALMS_DIR/${alias}.env"
  fi
}

# "local" ou "equipe" — de onde o realm resolvido para esse alias está vindo.
realm_origin() {
  local alias="$1"
  if [ -f "$REALMS_DIR/${alias}.env" ]; then
    printf 'local'
  elif [ -f "$TEAM_REALMS_DIR/${alias}.env" ]; then
    printf 'equipe'
  fi
}

list_realm_aliases() {
  local f
  {
    if [ -d "$REALMS_DIR" ]; then
      for f in "$REALMS_DIR"/*.env; do [ -e "$f" ] && basename "$f" .env; done
    fi
    if [ -d "$TEAM_REALMS_DIR" ]; then
      for f in "$TEAM_REALMS_DIR"/*.env; do [ -e "$f" ] && basename "$f" .env; done
    fi
  } | sort -u
}

# Lê um arquivo KEY=VALUE (client/user/realm .env) SEM usar `source`/`eval`/`declare` com
# nome de variável vindo do arquivo — evita execução de comando embutido no valor (ex:
# $(...), crase) e evita que uma chave arbitrária no arquivo (ex: "PATH=", "IFS=") sobrescreva
# uma variável de shell não relacionada. Só as variáveis passadas explicitamente em $2... são
# aceitas (allowlist); qualquer outra linha/chave no arquivo é ignorada silenciosamente. Faz
# split só no PRIMEIRO "=" da linha, então valores contendo "=" (comum em secret em base64)
# não são truncados. As variáveis pedidas SEMPRE ficam definidas ao final (vazias se ausentes
# no arquivo), pra nunca herdar valor de uma chamada anterior no mesmo processo.
load_env_file_safe() {
  local file="$1"; shift
  local wanted=("$@")
  local line key value w

  for w in "${wanted[@]}"; do
    printf -v "$w" '%s' ""
  done

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    for w in "${wanted[@]}"; do
      if [ "$key" = "$w" ]; then
        printf -v "$key" '%s' "$value"
        break
      fi
    done
  done < "$file"
}

# Carrega uma credencial (client ou user, o que existir para o alias) + o realm que ela
# referencia. Define KEYCLOAK_BASE_URL, KEYCLOAK_REALM, KEYCLOAK_REALM_ALIAS,
# KEYCLOAK_AUTH_TYPE (client_credentials|password) e os campos específicos do tipo
# (CLIENT_SECRET, ou USERNAME/PASSWORD) como variáveis de shell simples (não exportadas) no
# processo chamador. Lê os arquivos .env com load_env_file_safe (sem `source`) — os valores
# (client_secret, senha, username, base URL) podem vir de texto digitado/colado pelo usuário
# ou, no caso de realms de equipe, de um PR de terceiro versionado no repo da skill, e nunca
# devem ser interpretados como código bash.
load_credential_env() {
  local alias="$1"
  local client_env="$CLIENTS_DIR/${alias}.env"
  local user_env="$USERS_DIR/${alias}.env"

  # Reseta os campos específicos de tipo ANTES de carregar — impede que uma credencial
  # carregada antes (ex: origem, num espelhamento) deixe secret/senha residual quando a
  # credencial atual é de outro tipo.
  KEYCLOAK_CLIENT_SECRET=""
  KEYCLOAK_USERNAME=""
  KEYCLOAK_PASSWORD=""

  if [ -f "$client_env" ]; then
    load_env_file_safe "$client_env" KEYCLOAK_REALM_ALIAS KEYCLOAK_CLIENT_ID KEYCLOAK_CLIENT_SECRET
    KEYCLOAK_AUTH_TYPE="client_credentials"
  elif [ -f "$user_env" ]; then
    load_env_file_safe "$user_env" KEYCLOAK_REALM_ALIAS KEYCLOAK_CLIENT_ID KEYCLOAK_USERNAME KEYCLOAK_PASSWORD
    KEYCLOAK_AUTH_TYPE="password"
  else
    echo "Credencial não encontrada para '${alias}' (procurado em clients/ e users/)." >&2
    echo "Rode: kc setup-client   ou, para credencial de usuário: kc setup-user" >&2
    exit 1
  fi

  local realm_env
  realm_env="$(resolve_realm_env_file "$KEYCLOAK_REALM_ALIAS")"
  if [ -z "$realm_env" ]; then
    echo "Realm '${KEYCLOAK_REALM_ALIAS}' (referenciado por '${alias}') não encontrado — procurado em $REALMS_DIR e $TEAM_REALMS_DIR." >&2
    exit 1
  fi
  load_env_file_safe "$realm_env" KEYCLOAK_BASE_URL KEYCLOAK_REALM
}

# Aborta com mensagem clara se o alias já existir do "outro lado" (client vs user) —
# evita duas credenciais com o mesmo nome e tipos diferentes brigando por resolução.
check_alias_not_used_elsewhere() {
  local alias="$1" other_dir="$2" other_label="$3"
  if [ -f "$other_dir/${alias}.env" ]; then
    echo "Alias '${alias}' já está cadastrado como ${other_label}. Escolha outro nome." >&2
    exit 1
  fi
}

# Repete a pergunta até vir um valor não-vazio.
read_required() {
  local prompt="$1"
  local value=""
  while [ -z "$value" ]; do
    read -rp "$prompt" value
    [ -z "$value" ] && echo "  -> não pode ficar vazio, tente de novo." >&2
  done
  printf '%s' "$value"
}

# Como read_required, mas com valor padrão (usado ao editar um cadastro existente):
# Enter mantém o default; só repete se não houver default nem valor digitado.
read_required_default() {
  local label="$1" default="$2" value=""
  local prompt="$label"
  [ -n "$default" ] && prompt="$prompt [$default]"
  prompt="$prompt: "
  while true; do
    read -rp "$prompt" value
    if [ -z "$value" ]; then
      if [ -n "$default" ]; then
        printf '%s' "$default"
        return 0
      fi
      echo "  -> não pode ficar vazio, tente de novo." >&2
      continue
    fi
    printf '%s' "$value"
    return 0
  done
}

# Lê um segredo char a char sem ecoar o valor real — cada caractere digitado ou colado vira
# um "*" na tela imediatamente, então dá pra conferir visualmente que colou (e não colou em
# dobro) antes de confirmar, em vez de descobrir só depois pelo tamanho salvo. Backspace apaga
# o último "*". Enter finaliza.
read_secret_masked() {
  local prompt="$1"
  local secret="" char
  printf '%s' "$prompt" >&2
  while IFS= read -r -s -n 1 char; do
    if [ -z "$char" ]; then
      break
    fi
    if [ "$char" = $'\x7f' ] || [ "$char" = $'\x08' ]; then
      if [ -n "$secret" ]; then
        secret="${secret%?}"
        printf '\b \b' >&2
      fi
      continue
    fi
    secret+="$char"
    printf '*' >&2
  done
  printf '\n' >&2
  printf '%s' "$secret"
}

# Imprime uma barra de "*" do tamanho da string, para conferência visual do comprimento
# (ex: mostrar o secret já salvo sem revelar o valor).
mask_bar() {
  local len="$1"
  [ "$len" -gt 0 ] || return 0
  printf '*%.0s' $(seq 1 "$len")
}

# Faz uma chamada HTTP e trata erro de forma legível. Sem isso, um `curl -f | python3 -c
# "json.load(...)"` recebe stdin vazio em qualquer erro HTTP (curl -f descarta o corpo) e
# quebra com um traceback de JSONDecodeError em vez de dizer o que realmente aconteceu
# (403 sem permissão, 401 credencial inválida, etc). Uso:
#   BODY="$(api_request GET "$URL" -H "Authorization: Bearer $TOKEN")" || exit 1
# Em sucesso (2xx), imprime o corpo em stdout e retorna 0. Em erro, imprime em stderr
# "Erro HTTP <status> em <method> <url>" + a mensagem do Keycloak (campo errorMessage/
# error_description/error, se o corpo for JSON) e retorna 1 — nunca propaga o corpo bruto
# nem token/secret (que só aparecem nos argumentos de requisição, não na resposta de erro).
api_request() {
  local method="$1" url="$2"
  shift 2
  local body_file status
  body_file="$(mktemp)"
  status="$(curl -s -o "$body_file" -w '%{http_code}' -X "$method" "$url" "$@")"
  if [ "$status" -ge 200 ] && [ "$status" -lt 300 ]; then
    cat "$body_file"
    rm -f "$body_file"
    return 0
  fi
  {
    echo "Erro HTTP ${status} em ${method} ${url}"
    python3 -c "
import json
try:
    with open('$body_file') as f:
        data = json.load(f)
    if isinstance(data, dict):
        msg = data.get('errorMessage') or data.get('error_description') or data.get('error')
        if msg:
            print(msg)
except Exception:
    pass
"
    # 403 na Admin REST API quase sempre é falta de role, não bug — o Keycloak tem escopos
    # bem diferentes conforme o tipo de credencial: um client sem roles de service account
    # atribuídas só enxerga a si mesmo (ou nada), e um usuário sem role de realm-management
    # também apanha, mesmo autenticando com sucesso. A dica evita o usuário ficar arquitetando
    # hipóteses — aponta direto o que falta configurar no Keycloak.
    if [ "$status" = "403" ]; then
      case "${KEYCLOAK_AUTH_TYPE:-}" in
        client_credentials)
          echo
          echo "Dica: essa credencial é um CLIENT (service account, grant_type=client_credentials)."
          echo "O service account desse client precisa de roles do client 'realm-management' no realm consultado — ex: 'view-clients'/'view-realm' (leitura) ou 'realm-admin' (completo)."
          echo "Configurar em: Clients > <esse client> > Service accounts roles > Assign role > filtrar por 'realm-management'."
          ;;
        password)
          echo
          echo "Dica: essa credencial é um USUÁRIO (grant_type=password)."
          echo "Duas saídas: (a) atribuir ao usuário roles do client 'realm-management' no realm consultado (ex: 'view-clients'/'view-realm' ou 'realm-admin'); ou"
          echo "(b) se o usuário for admin do realm 'master' da mesma instância, rodar o comando passando o nome do REALM (não o alias da credencial) como argumento — o script resolve sozinho uma credencial de master para essa instância."
          ;;
      esac
    fi
  } >&2
  rm -f "$body_file"
  return 1
}

MASTER_DEFAULTS_DIR="$SECRETS_ROOT/master-defaults"

# Sanitiza uma base URL para nome de arquivo (troca tudo que não for alfanumérico por "_").
_sanitize_base_url() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'
}

# Lê UM campo de um .env em subshell — nunca deixa a variável (ex: KEYCLOAK_BASE_URL) presa
# por escopo dinâmico no frame de quem chamou; só o valor cruza de volta, via stdout.
_env_field() {
  local file="$1" field="$2"
  ( load_env_file_safe "$file" "$field"; printf '%s' "${!field}" )
}

# Imprime (um por linha) os aliases de client/user cujo realm associado tem a mesma base URL
# informada e nome técnico de realm "master" — candidatos a admin cross-realm da instância.
# Roda isolado via process substitution no chamador; nada aqui vaza para fora.
_master_candidates_for_base_url() {
  local base_url="$1" dir f alias realm_alias realm_env c_base c_realm
  for dir in "$CLIENTS_DIR" "$USERS_DIR"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.env; do
      [ -e "$f" ] || continue
      alias="$(basename "$f" .env)"
      realm_alias="$(_env_field "$f" KEYCLOAK_REALM_ALIAS)"
      [ -n "$realm_alias" ] || continue
      realm_env="$(resolve_realm_env_file "$realm_alias")"
      [ -n "$realm_env" ] || continue
      c_base="$(_env_field "$realm_env" KEYCLOAK_BASE_URL)"
      c_realm="$(_env_field "$realm_env" KEYCLOAK_REALM)"
      if [ "$c_base" = "$base_url" ] && [ "$c_realm" = "master" ]; then
        printf '%s\n' "$alias"
      fi
    done
  done
}

# Imprime o credAlias salvo como padrão de master para essa base URL, ou nada se não houver.
get_master_default_for_base_url() {
  local base_url="$1" f
  f="$MASTER_DEFAULTS_DIR/$(_sanitize_base_url "$base_url").env"
  [ -f "$f" ] || return 0
  _env_field "$f" CRED_ALIAS
}

# Salva um credAlias como padrão de master para essa base URL (usado quando há mais de um
# candidato e o usuário escolhe persistir a escolha).
set_master_default_for_base_url() {
  local base_url="$1" cred_alias="$2" f
  mkdir -p "$MASTER_DEFAULTS_DIR"
  chmod 700 "$MASTER_DEFAULTS_DIR"
  f="$MASTER_DEFAULTS_DIR/$(_sanitize_base_url "$base_url").env"
  printf 'CRED_ALIAS=%s\n' "$cred_alias" > "$f"
  chmod 600 "$f"
}

# Resolve credencial + realm técnico a consultar a partir do 1º argumento de um comando de
# consulta (list-clients, client-roles, realm-roles, list-groups, group-detail). Aceita duas
# formas:
#   1) <credAlias> [realmDestino] — comportamento explícito de sempre: usa essa credencial; o
#      2º argumento (opcional) sobrescreve o realm consultado (senão usa o realm da própria
#      credencial).
#   2) <realmAlias> — um REALM cadastrado (não uma credencial): resolve automaticamente uma
#      credencial de admin do realm "master" da MESMA instância (mesma base URL) para
#      consultar esse realm — cobre o padrão de admin do master gerenciando qualquer realm da
#      instância. Zero candidatos -> erro pedindo setup. Um candidato (ou um default salvo) ->
#      usa direto. Mais de um sem default -> menu interativo + oferece salvar como padrão.
# Ao final, deixa definidos no processo chamador: CRED_ALIAS, TARGET_REALM, e (via
# load_credential_env) KEYCLOAK_BASE_URL/KEYCLOAK_REALM/etc da credencial escolhida.
resolve_target_credential() {
  local arg1="$1" realm_override="${2:-}"

  if [ -f "$CLIENTS_DIR/${arg1}.env" ] || [ -f "$USERS_DIR/${arg1}.env" ]; then
    CRED_ALIAS="$arg1"
    load_credential_env "$CRED_ALIAS"
    TARGET_REALM="${realm_override:-$KEYCLOAK_REALM}"
    return 0
  fi

  local realm_env
  realm_env="$(resolve_realm_env_file "$arg1")"
  if [ -z "$realm_env" ]; then
    echo "'${arg1}' não é uma credencial nem um realm cadastrado (procurado em clients/, users/ e realms/)." >&2
    echo "Rode: kc setup-client / kc setup-user (credencial)   ou   kc setup-realm (realm)." >&2
    exit 1
  fi

  # As leituras abaixo usam _env_field (subshell) em vez de `local KEYCLOAK_BASE_URL/...` +
  # load_env_file_safe direto: como esta função ainda chama load_credential_env mais abaixo
  # (que define KEYCLOAK_BASE_URL/KEYCLOAK_REALM como variável do PROCESSO CHAMADOR), uma
  # `local` com esse mesmo nome aqui sequestraria essas atribuições por escopo dinâmico do
  # bash — o valor ficaria preso neste frame e sumiria ao retornar, deixando
  # KEYCLOAK_BASE_URL indefinida no script chamador (foi exatamente o bug observado).
  local target_base_url
  target_base_url="$(_env_field "$realm_env" KEYCLOAK_BASE_URL)"
  TARGET_REALM="$(_env_field "$realm_env" KEYCLOAK_REALM)"

  local candidates=()
  while IFS= read -r alias; do
    [ -n "$alias" ] && candidates+=("$alias")
  done < <(_master_candidates_for_base_url "$target_base_url")

  if [ "${#candidates[@]}" -eq 0 ]; then
    echo "'${arg1}' é um realm cadastrado, mas não há credencial de admin do realm 'master' para a instância ${target_base_url}." >&2
    echo "Cadastre uma: kc setup-realm (realm técnico 'master', mesma base URL) + kc setup-user." >&2
    exit 1
  fi

  local chosen="" default_alias
  default_alias="$(get_master_default_for_base_url "$target_base_url")"
  if [ -n "$default_alias" ] && printf '%s\n' "${candidates[@]}" | grep -qx "$default_alias"; then
    chosen="$default_alias"
  elif [ "${#candidates[@]}" -eq 1 ]; then
    chosen="${candidates[0]}"
  else
    echo "Mais de uma credencial de master encontrada para ${target_base_url}:" >&2
    local opt
    PS3="Qual usar para consultar '${arg1}'? "
    select opt in "${candidates[@]}"; do
      if [ -n "${opt:-}" ]; then chosen="$opt"; break; fi
      echo "Opção inválida, escolha um número da lista." >&2
    done
    local SAVE_DEFAULT=""
    read -rp "Usar sempre '${chosen}' como padrão para esta instância (${target_base_url})? [s/N] " SAVE_DEFAULT
    case "$SAVE_DEFAULT" in
      [sS]|[sS][iI][mM]) set_master_default_for_base_url "$target_base_url" "$chosen" ;;
    esac
  fi

  echo "Usando credencial de master '${chosen}' para consultar o realm '${arg1}' (${TARGET_REALM})." >&2
  CRED_ALIAS="$chosen"
  load_credential_env "$CRED_ALIAS"
}
