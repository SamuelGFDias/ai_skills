#!/usr/bin/env bash
# ctvl — CLI único da skill ctvl-api. Só delega (exec) para os scripts individuais.
set -euo pipefail

# readlink -f resolve symlinks (ex.: ~/.local/bin/ctvl) até a pasta real dos scripts.
CTVLMAIN_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

usage() {
  cat >&2 <<'USO'
ctvl — gerencia o CT-VL (CipherTrust Vaulted Tokenization) pela API admin

Uso: ctvl.sh <subcomando> [args...]        (ambiente = dev | hml | prd, apelidos do arquivo de credenciais)

Cadastro e autenticação:
  setup-env <ambiente>                     Cadastra credenciais (interativo, senha mascarada, modo 600, fora do git).
  envs                                     Lista ambientes configurados (sem host/usuário/senha).
  token <ambiente> [--refresh|--status]    Garante o JWT em cache (modo 600). Nunca imprime o token.

Cliente genérico:
  admin <ambiente> <MÉTODO> <path> [--body-file F|--body-stdin|--body JSON] [--query k=v] [--all] [--yes]
                                           Escrita (POST/PUT/PATCH/DELETE) exige --yes e mostra o que vai fazer.

Leitura da configuração atual:
  list <ambiente> <recurso> [--format table|yaml|json]
                                           recurso: masks users groups tokengroups templates charsets keys formats permissions all
  export <ambiente> [--out ARQUIVO.yaml]   YAML declarativo determinístico, sem segredos (para versionar).
  probe-refs <ambiente>                    Evidência de nome x id nas referências (sem imprimir valores).

Declarativo (idempotente; nunca deleta):
  plan  <ambiente|--offline> --file CFG.yaml | --docs-dir DIR [--empty-state|--state-dir DIR] ...   (saída compacta; --verbose ou CTVL_VERBOSE=1 = texto completo)
  apply <ambiente> --file CFG.yaml | --docs-dir DIR --yes [--skip-blocked] [--allow-breaking-update]

  enable-detokenize <ambiente> <usuario> --file CFG.yaml | --docs-dir DIR [--yes] [--sample VALOR_FABRICADO]
                                           ÚNICO caminho que escreve canGet=true para perfil MASCARADO (o apply nunca
                                           escreve). Um usuário por vez; sem --yes é dry-run; recusa se a máscara
                                           atribuída não for exatamente a declarada, se algum grupo tiver canGet=true
                                           ou se o verify-mask falhar (reverte para canGet=false).

Verificação e utilidades:
  verify-mask <ambiente> --file CFG.yaml --sistema S --datatype D --sample VALOR_FABRICADO
  names NOME... [--kind user|mask] [--file CFG.yaml]   Valida nomes <sistema>_<datatype>[_<esquema>] (offline).
  check-config --file CFG.yaml | --docs-dir DIR        Valida e resume a configuração (offline).

Ex.: ctvl.sh list dev users | ctvl.sh export dev --out ctvl-dev.yaml | ctvl.sh plan dev --file ctvl-dev.yaml
USO
}

sub="${1:-}"
if [ -n "$sub" ]; then
  shift
fi
case "$sub" in
  setup-env) exec "$CTVLMAIN_DIR/ctvl-setup-env.sh" "$@" ;;
  envs) exec "$CTVLMAIN_DIR/ctvl-envs.sh" "$@" ;;
  token) exec "$CTVLMAIN_DIR/ctvl-token.sh" "$@" ;;
  admin) exec "$CTVLMAIN_DIR/ctvl-admin.sh" "$@" ;;
  list) exec "$CTVLMAIN_DIR/ctvl-list.sh" "$@" ;;
  export) exec "$CTVLMAIN_DIR/ctvl-export.sh" "$@" ;;
  probe-refs) exec "$CTVLMAIN_DIR/ctvl-probe-refs.sh" "$@" ;;
  plan) exec "$CTVLMAIN_DIR/ctvl-plan.sh" "$@" ;;
  apply) exec "$CTVLMAIN_DIR/ctvl-apply.sh" "$@" ;;
  enable-detokenize) exec "$CTVLMAIN_DIR/ctvl-enable-detokenize.sh" "$@" ;;
  verify-mask) exec "$CTVLMAIN_DIR/ctvl-verify-mask.sh" "$@" ;;
  names | check-config) exec python3 -B "$CTVLMAIN_DIR/ctvl_core.py" "$sub" "$@" ;;
  '' | -h | --help | help) usage; exit 0 ;;
  *)
    echo "Subcomando desconhecido: $sub" >&2
    usage
    exit 1
    ;;
esac
