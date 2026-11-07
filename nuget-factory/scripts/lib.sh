#!/usr/bin/env bash
# Funções compartilhadas pelos scripts nexus-*.sh
set -euo pipefail

NEXUS_HOST="https://nexus.example.com"
NEXUS_USER="${NEXUS_USER:-}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Comando obrigatorio ausente: $1" >&2
    exit 1
  }
}

require_cmd curl
require_cmd jq

# Localiza o despachante vault-read: PATH primeiro, depois o clone padrao das skills.
_vault_read_bin() {
  if command -v vault-read >/dev/null 2>&1; then
    command -v vault-read
  elif [[ -x "$HOME/.config/ai/skills/vault-factory/scripts/vault-read.sh" ]]; then
    printf '%s' "$HOME/.config/ai/skills/vault-factory/scripts/vault-read.sh"
  else
    return 1
  fi
}

# Define a referencia da senha em NEXUS_REF. Prioridade: NEXUS_PASSWORD_REF; senao o legado
# NEXUS_PASSBOLT_RESOURCE_ID (depreciado, com aviso em stderr sem o ID).
_nexus_ref() {
  if [[ -n "${NEXUS_PASSWORD_REF:-}" ]]; then
    NEXUS_REF="$NEXUS_PASSWORD_REF"
  elif [[ -n "${NEXUS_PASSBOLT_RESOURCE_ID:-}" ]]; then
    echo "AVISO: NEXUS_PASSBOLT_RESOURCE_ID esta depreciada; use NEXUS_PASSWORD_REF=<referencia-da-senha> (ex.: passbolt:<id-do-recurso>)." >&2
    NEXUS_REF="passbolt://${NEXUS_PASSBOLT_RESOURCE_ID}"
  else
    echo "NEXUS_PASSWORD_REF nao definida. Exporte a referencia da senha do Nexus (op://..., pass:..., gopass:..., passbolt:..., vault:...#chave)." >&2
    return 1
  fi
}

# Falha com mensagem util se NEXUS_USER nao estiver definida (sem valor padrao).
nexus_exige_usuario() {
  [[ -n "$NEXUS_USER" ]] || {
    echo "NEXUS_USER nao definida. Defina NEXUS_USER com o usuario do Nexus no ambiente (sem valor padrao)." >&2
    return 1
  }
}

# Verdadeiro se o valor tem \n ou \r: quebra a linha de config do curl e o XML do NuGet.Config.
nexus_tem_quebra_linha() {
  [[ "$1" == *$'\n'* || "$1" == *$'\r'* ]]
}

# Escreve em stdout a linha de config do curl (para "curl -K -") com usuario e senha.
# Escapa \ e " porque o parser de config do curl os interpreta dentro de aspas.
# Recusa \n e \r: quebrariam a linha e o resto virava diretiva de config.
# Le NEXUS_USER e NEXUS_PASSWORD do ambiente; o valor nunca vai para argv nem para log.
curl_user_cfg() {
  local credencial="$NEXUS_USER:$NEXUS_PASSWORD"
  if nexus_tem_quebra_linha "$credencial"; then
    echo "NEXUS_USER ou senha do Nexus contem quebra de linha; nao suportada." >&2
    return 1
  fi
  credencial="${credencial//\\/\\\\}"
  credencial="${credencial//\"/\\\"}"
  printf 'user = "%s"\n' "$credencial"
}

# Executa um comando bash recebendo NEXUS_PASSWORD resolvida por vault-read.
# Uso: nexus_exec <comando> [NX_NOME=valor ...]
# O comando deve ser constante: valores de entrada entram so pelos pares NX_* (ambiente do
# filho) e o comando os referencia entre aspas duplas, por exemplo "$NX_REPO".
# A senha fica em variavel local e vai so para o ambiente do processo filho
# (nunca em argv, nunca em echo, nunca no shell pai).
nexus_exec() {
  local cmd="$1" vr senha par
  shift
  nexus_exige_usuario || return 1
  if nexus_tem_quebra_linha "$NEXUS_USER"; then
    echo "NEXUS_USER contem quebra de linha; nao suportada." >&2
    return 1
  fi
  for par in "$@"; do
    [[ "$par" =~ ^NX_[A-Z0-9_]+= ]] || {
      echo "nexus_exec: parametro invalido (esperado NX_NOME=valor): ${par%%=*}" >&2
      return 1
    }
  done
  _nexus_ref || return 1
  vr="$(_vault_read_bin)" || {
    echo "vault-read nao encontrado (PATH ou ~/.config/ai/skills/vault-factory/scripts/vault-read.sh)." >&2
    return 1
  }
  senha="$("$vr" "$NEXUS_REF")" || {
    echo "Falha ao ler a senha do Nexus pela referencia informada." >&2
    return 1
  }
  # Checado aqui e nao so em curl_user_cfg: dentro do pipe "curl_user_cfg | curl" a falha do
  # primeiro lado nao impede o curl de rodar sem config.
  if nexus_tem_quebra_linha "$senha"; then
    echo "Senha do Nexus contem quebra de linha; nao suportada." >&2
    return 1
  fi
  # Subshell: export -f so vale para o filho, e curl_user_cfg fica disponivel dentro do cmd.
  (
    export -f curl_user_cfg
    for par in "$@"; do export "$par"; done
    NEXUS_USER="$NEXUS_USER" NEXUS_PASSWORD="$senha" bash -c "$cmd"
  )
}
