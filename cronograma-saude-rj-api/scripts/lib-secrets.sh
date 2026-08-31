#!/usr/bin/env bash
# lib-secrets.sh — funções compartilhadas por login.sh e setup-login.sh.
# Sempre sourced (nunca executado diretamente). Não imprime secret em nenhuma função.
#
# Modelo de armazenamento (mais simples que o do keycloak-api: não há conceito de
# realm/client aqui, só usuário/senha por alias):
#   ~/.claude/secrets/cronograma/users/<alias>.env -> CRONOGRAMA_USERNAME, CRONOGRAMA_PASSWORD

SECRETS_ROOT="$HOME/.claude/secrets/cronograma"
USERS_DIR="$SECRETS_ROOT/users"

# Lê um arquivo KEY=VALUE SEM usar `source`/`eval`/`declare` com nome de variável vindo do
# arquivo — evita execução de comando embutido no valor (ex: $(...), crase) e evita que uma
# chave arbitrária no arquivo sobrescreva uma variável de shell não relacionada. Só as
# variáveis passadas explicitamente em $2... são aceitas (allowlist); qualquer outra
# linha/chave no arquivo é ignorada silenciosamente. Faz split só no PRIMEIRO "=" da linha,
# então valores contendo "=" não são truncados. As variáveis pedidas SEMPRE ficam definidas
# ao final (vazias se ausentes no arquivo), pra nunca herdar valor de uma chamada anterior no
# mesmo processo.
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
# (ex: mostrar a senha já salva sem revelar o valor).
mask_bar() {
  local len="$1"
  [ "$len" -gt 0 ] || return 0
  printf '*%.0s' $(seq 1 "$len")
}

# Carrega a credencial de usuário/senha do alias informado, definindo CRONOGRAMA_USERNAME e
# CRONOGRAMA_PASSWORD no processo chamador. Lê o arquivo .env com load_env_file_safe (sem
# `source`) — o valor (senha) pode vir de texto digitado/colado pelo usuário e nunca deve ser
# interpretado como código bash.
load_cronograma_credential() {
  local alias="$1"
  local env_file="$USERS_DIR/${alias}.env"

  if [ ! -f "$env_file" ]; then
    echo "Credencial '${alias}' não encontrada. Rode: setup-login.sh" >&2
    exit 1
  fi

  load_env_file_safe "$env_file" CRONOGRAMA_USERNAME CRONOGRAMA_PASSWORD
}
