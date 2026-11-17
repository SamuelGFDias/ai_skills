#!/usr/bin/env bash
# CLI de conteudo do portfolio (API /api/content e /api/upload).
# Config: PORTFOLIO_URL e um de PORTFOLIO_TOKEN_FILE | PORTFOLIO_TOKEN_REF (vault-read),
# lidos do ambiente ou de ~/.config/portfolio-conteudo/env. O token nunca e impresso nem vai em argv.
set -euo pipefail

CONF_DIR="${PORTFOLIO_CONF_DIR:-$HOME/.config/portfolio-conteudo}"
if [ -f "$CONF_DIR/env" ]; then
  # shellcheck disable=SC1091
  . "$CONF_DIR/env"
fi
PF_URL="${PORTFOLIO_URL:-}"
PF_TOKEN_FILE="${PORTFOLIO_TOKEN_FILE:-}"
PF_TOKEN_REF="${PORTFOLIO_TOKEN_REF:-}"

pf_die() { printf 'portfolio: %s\n' "$*" >&2; exit 1; }
pf_need_url() { [ -n "$PF_URL" ] || pf_die "defina PORTFOLIO_URL (ambiente ou $CONF_DIR/env)"; }

# Cria um arquivo de cabecalho 0600 com o token e devolve o caminho em PF_HDR.
pf_auth() {
  PF_HDR="$(mktemp)"; chmod 600 "$PF_HDR"
  trap 'rm -f "$PF_HDR"' EXIT
  if [ -n "$PF_TOKEN_FILE" ]; then
    [ -r "$PF_TOKEN_FILE" ] || pf_die "nao consigo ler PORTFOLIO_TOKEN_FILE"
    { printf 'Authorization: Bearer '; tr -d '\r\n' < "$PF_TOKEN_FILE"; printf '\n'; } > "$PF_HDR"
  elif [ -n "$PF_TOKEN_REF" ]; then
    command -v vault-read >/dev/null || pf_die "vault-read ausente (skill vault-factory, scripts/init.sh)"
    { printf 'Authorization: Bearer '; vault-read "$PF_TOKEN_REF"; printf '\n'; } > "$PF_HDR"
  else
    pf_die "defina PORTFOLIO_TOKEN_FILE ou PORTFOLIO_TOKEN_REF"
  fi
}

pf_backup() {
  mkdir -p "$CONF_DIR/backups"; chmod 700 "$CONF_DIR" "$CONF_DIR/backups"
  local out; out="$CONF_DIR/backups/$(date -u +%Y%m%dT%H%M%SZ).json"
  curl -fsS -m 30 "$PF_URL/api/content" -o "$out" || pf_die "falha ao baixar o conteudo para backup"
  printf '%s\n' "$out"
}

pf_put() { # $1 = arquivo JSON com as secoes a gravar
  local code
  code="$(curl -sS -m 90 -o /dev/null -w '%{http_code}' -X PUT -H @"$PF_HDR" -H 'Content-Type: application/json' --data-binary @"$1" "$PF_URL/api/content")"
  [ "$code" = "200" ] || pf_die "PUT /api/content respondeu $code"
  printf 'gravado (HTTP 200)\n'
}

cmd="${1:-help}"; shift || true
case "$cmd" in
  get) # get [secao]
    pf_need_url
    curl -fsS -m 30 "$PF_URL/api/content" | python3 -c '
import json, sys
d = json.load(sys.stdin); k = sys.argv[1] if len(sys.argv) > 1 else None
if k and k not in d: sys.exit(f"secao inexistente: {k}. Existem: {sorted(d)}")
json.dump(d[k] if k else d, sys.stdout, ensure_ascii=False, indent=2); print()' "$@"
    ;;
  backup)
    pf_need_url; pf_backup
    ;;
  put) # put <arquivo.json>  — o arquivo tem as secoes de topo a substituir, ex.: {"commercial": {...}}
    [ $# -eq 1 ] && [ -r "$1" ] || pf_die "uso: portfolio put <arquivo.json>"
    pf_need_url; python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert isinstance(d,dict) and d, "JSON precisa ser um objeto com secoes"' "$1"
    pf_auth; printf 'backup: %s\n' "$(pf_backup)"; pf_put "$1"
    ;;
  set) # set <secao> <campo> <valor>  — altera um campo de texto de uma secao (ex.: commercial heroTitle "...")
    [ $# -eq 3 ] || pf_die "uso: portfolio set <secao> <campo> <valor>"
    pf_need_url; pf_auth; printf 'backup: %s\n' "$(pf_backup)"
    tmp="$(mktemp)"; trap 'rm -f "$PF_HDR" "$tmp"' EXIT
    curl -fsS -m 30 "$PF_URL/api/content" | python3 -c '
import json, sys
d = json.load(sys.stdin); sec, key, val = sys.argv[1:4]
if sec not in d: sys.exit(f"secao inexistente: {sec}")
if key not in d[sec] or not isinstance(d[sec][key], str): sys.exit(f"campo de texto inexistente em {sec}: {key}")
d[sec][key] = val; json.dump({sec: d[sec]}, open(sys.argv[4], "w"), ensure_ascii=False)' "$1" "$2" "$3" "$tmp"
    pf_put "$tmp"
    ;;
  project-upsert) # project-upsert <projeto.json>  — cria ou atualiza um projeto pelo "id", preservando os outros
    [ $# -eq 1 ] && [ -r "$1" ] || pf_die "uso: portfolio project-upsert <projeto.json>"
    pf_need_url; pf_auth; printf 'backup: %s\n' "$(pf_backup)"
    tmp="$(mktemp)"; trap 'rm -f "$PF_HDR" "$tmp"' EXIT
    curl -fsS -m 30 "$PF_URL/api/content" | python3 -c '
import json, sys
d = json.load(sys.stdin); new = json.load(open(sys.argv[1]))
if not isinstance(new, dict) or not new.get("id"): sys.exit("o projeto precisa de um campo id")
base = dict(title="", shortDescription="", description="", objective="", technologies=[], imageUrl="", githubUrl="", liveUrl="", screenshots=[])
items = d["projects"]["items"]
for i, p in enumerate(items):
    if p["id"] == new["id"]:
        items[i] = {**p, **new}; print("atualizado:", new["id"], file=sys.stderr); break
else:
    items.append({**base, **new}); print("criado:", new["id"], file=sys.stderr)
json.dump({"projects": d["projects"]}, open(sys.argv[2], "w"), ensure_ascii=False)' "$1" "$tmp"
    pf_put "$tmp"
    ;;
  upload) # upload <arquivo> <pasta>  — ex.: upload tela.png projects/proj-x ; imprime a URL para usar no conteudo
    [ $# -eq 2 ] && [ -r "$1" ] || pf_die "uso: portfolio upload <arquivo> <pasta, ex.: projects/proj-x>"
    pf_need_url; pf_auth
    curl -fsS -m 180 -H @"$PF_HDR" -F "path=$2" -F "file=@$1" "$PF_URL/api/upload" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if "url" not in d: sys.exit(str(d))
print(d["url"])'
    ;;
  *)
    cat <<'USO'
portfolio get [secao]                      le o conteudo (publico)
portfolio backup                           salva uma copia local do conteudo
portfolio set <secao> <campo> <valor>      altera um campo de texto
portfolio project-upsert <projeto.json>    cria ou atualiza um projeto pelo id
portfolio upload <arquivo> <pasta>         envia imagem e imprime a URL
portfolio put <arquivo.json>               substitui secoes inteiras (use por ultimo)
USO
    ;;
esac
