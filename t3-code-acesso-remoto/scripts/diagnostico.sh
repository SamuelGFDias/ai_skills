#!/usr/bin/env bash
# Diagnóstico somente leitura do acesso remoto ao T3 Code.
# Não altera serviço, atalhos, Tailscale nem o app. Só lê e testa.
#
# uso: diagnostico.sh [nome-do-celular-na-tailnet]
#   padrão do celular: iphone-xr (troque pelo nome do seu aparelho)
set -uo pipefail

PHONE=${1:-iphone-xr}
SERVICE_HOME=${SERVICE_HOME:-$HOME/.t3}
DESKTOP_HOME=${DESKTOP_HOME:-$HOME/.t3-desktop}
T3_BIN=${T3_BIN:-$HOME/.t3/bin/t3}

ok()   { echo "[OK]        $*"; }
warn() { echo "[ATENCAO]   $*"; }
info() { echo "[INFO]      $*"; }

runtime_field() { grep -o "\"$2\":[^,}]*" "$1" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' "'; }

echo "== 1. Serviço em background"
if systemctl --user is-enabled t3code >/dev/null 2>&1; then ok "t3code habilitado"; else warn "t3code não está habilitado (systemctl --user enable --now t3code)"; fi
if systemctl --user is-active t3code >/dev/null 2>&1; then ok "t3code ativo"; else warn "t3code inativo"; fi
SVC_ENV=$(systemctl --user show t3code -p Environment 2>/dev/null)
case "$SVC_ENV" in
  *T3CODE_HOME=*) info "unit: $(echo "$SVC_ENV" | grep -o 'T3CODE_HOME=[^ ]*')" ;;
  *) warn "unit sem T3CODE_HOME explícito (o padrão é ~/.t3)" ;;
esac

SVC_RUNTIME="$SERVICE_HOME/userdata/server-runtime.json"
SVC_PORT=""
SVC_PID=""
if [ -f "$SVC_RUNTIME" ]; then
  SVC_PORT=$(runtime_field "$SVC_RUNTIME" port)
  SVC_PID=$(runtime_field "$SVC_RUNTIME" pid)
  info "serviço: pid=$SVC_PID porta=$SVC_PORT (home $SERVICE_HOME)"
else
  warn "sem $SVC_RUNTIME (serviço não subiu neste home)"
fi

echo
echo "== 2. Desktop em diretório separado"
DESK_RUNTIME="$DESKTOP_HOME/userdata/server-runtime.json"
if [ -f "$DESK_RUNTIME" ]; then
  DESK_PID=$(runtime_field "$DESK_RUNTIME" pid)
  if [ -n "$SVC_PID" ] && [ "$DESK_PID" = "$SVC_PID" ]; then
    warn "desktop e serviço compartilham o mesmo processo (pid $DESK_PID): diretórios não estão separados"
  else
    ok "desktop usa $DESKTOP_HOME (pid $DESK_PID), separado do serviço"
  fi
else
  info "desktop ainda não gravou $DESK_RUNTIME (app fechado ou usando outro home)"
fi
for f in "$HOME/.local/share/applications/t3code.desktop" "$HOME/.config/autostart/t3code.desktop"; do
  if [ -f "$f" ]; then
    if grep -q "^Exec=.*T3CODE_HOME=$DESKTOP_HOME" "$f"; then
      ok "$(basename "$(dirname "$f")")/$(basename "$f") aponta para $DESKTOP_HOME"
    else
      warn "$f não define T3CODE_HOME=$DESKTOP_HOME no Exec"
    fi
  else
    info "$f não existe"
  fi
done
if [ -f "$HOME/.config/autostart/t3code.desktop" ]; then ok "autostart do desktop presente"; else info "sem autostart do desktop"; fi

echo
echo "== 3. Portas do T3 em escuta"
ss -ltnp 2>/dev/null | grep 'users:(("t3code"' | awk '{print $4}' | sort -u | sed 's/^/           /' || true
if [ -n "$SVC_PORT" ] && ss -ltn 2>/dev/null | grep -q "127.0.0.1:$SVC_PORT "; then
  ok "serviço escutando em 127.0.0.1:$SVC_PORT"
else
  [ -n "$SVC_PORT" ] && warn "nada escutando em 127.0.0.1:$SVC_PORT"
fi

echo
echo "== 4. Tailscale"
if command -v tailscale >/dev/null 2>&1; then
  TS_JSON=$(tailscale status --json 2>/dev/null || echo '{}')
  ts_field() { printf '%s' "$TS_JSON" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    d={}
v=d
for k in sys.argv[1].split("."):
    v=v.get(k,"") if isinstance(v,dict) else ""
print(v if v is not None else "")' "$1"; }
  STATE=$(ts_field BackendState)
  if [ "$STATE" = "Running" ]; then ok "Tailscale Running"; else warn "Tailscale em estado '${STATE:-desconhecido}'"; fi
  SUFFIX=$(ts_field MagicDNSSuffix)
  SELF_DNS=$(ts_field Self.DNSName | sed 's/\.$//')
  info "MagicDNS: ${SUFFIX:-desligado}  | nome deste nó: ${SELF_DNS:-?}"
  SERVE=$(tailscale serve status 2>/dev/null)
  if [ -n "$SERVE" ]; then
    echo "$SERVE" | sed 's/^/           /'
    if [ -n "$SVC_PORT" ] && echo "$SERVE" | grep -q "127.0.0.1:$SVC_PORT"; then
      ok "serve aponta para a porta do serviço ($SVC_PORT)"
    else
      warn "serve não aponta para 127.0.0.1:$SVC_PORT"
    fi
  else
    warn "sem configuração de tailscale serve"
  fi
  if [ -n "$SELF_DNS" ]; then
    CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "https://$SELF_DNS/.well-known/t3/environment" 2>/dev/null || echo "000")
    if [ "$CODE" = "200" ]; then ok "https://$SELF_DNS/.well-known/t3/environment respondeu 200"; else warn "endpoint HTTPS respondeu $CODE"; fi
  fi
  PING_OUT=$(mktemp)
  if timeout 25 tailscale ping -c 1 --timeout 5s "$PHONE" >"$PING_OUT" 2>&1 && grep -q '^pong' "$PING_OUT"; then
    ok "celular '$PHONE' respondeu ao ping pela tailnet ($(grep '^pong' "$PING_OUT" | head -1))"
  else
    warn "celular '$PHONE' sem resposta ao ping (VPN do Tailscale no celular desligada?)"
  fi
  rm -f "$PING_OUT"
else
  warn "comando tailscale não encontrado"
fi

echo
echo "== 5. Relay do T3 Connect (informativo)"
info "o acesso remoto desta skill não depende do relay; erros de relay podem ser ignorados"

echo
echo "Diagnóstico concluído. Itens [ATENCAO] indicam o que corrigir (ver SKILL.md)."
