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
# realm que também existe no arquivo versionado, ex: apontar sesrj-dev pra outra URL só
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
