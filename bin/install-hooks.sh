#!/usr/bin/env bash
# install-hooks.sh — ativa os git hooks versionados em .githooks/ neste repo (só bash; sem par .ps1).
#
# Opcional, por máquina. O que faz:
#   git config --local core.hooksPath .githooks   + chmod +x em .githooks/*
# Idempotente: rodar de novo não muda nada. Mexe só na config local deste repositório.
#
# --uninstall: remove core.hooksPath, mas só se ele apontar para .githooks (não mexe em outro valor).
#
# Uso:
#   bin/install-hooks.sh              # ativa e mostra o estado
#   bin/install-hooks.sh --uninstall  # desativa e mostra o estado
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR_NOME=".githooks"

usage() {
  cat <<'EOF'
Uso: bin/install-hooks.sh [--uninstall]

  (sem args)     define core.hooksPath=.githooks neste repo e torna os hooks executáveis
  --uninstall    remove core.hooksPath se apontar para .githooks
EOF
  return 0
}

MODO="instalar"
case "${1:-}" in
  "") ;;
  --uninstall) MODO="desinstalar" ;;
  -h|--help) usage; exit 0 ;;
  *) echo "opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
esac

ATUAL="$(git -C "$REPO_DIR" config --local --get core.hooksPath 2>/dev/null || true)"

mostrar_estado() {
  local valor
  valor="$(git -C "$REPO_DIR" config --local --get core.hooksPath 2>/dev/null || true)"
  if [ -z "$valor" ]; then
    echo "Estado: core.hooksPath não definido neste repo (hooks do git desativados)."
  else
    echo "Estado: core.hooksPath=$valor"
  fi
  local h
  for h in "$REPO_DIR/$HOOKS_DIR_NOME"/*; do
    [ -f "$h" ] || continue
    if [ -x "$h" ]; then
      echo "  hook: $(basename "$h") (executável)"
    else
      echo "  hook: $(basename "$h") (NÃO executável)"
    fi
  done
  return 0
}

if [ "$MODO" = "instalar" ]; then
  if [ "$ATUAL" = "$HOOKS_DIR_NOME" ]; then
    echo "core.hooksPath já é $HOOKS_DIR_NOME; nada a configurar."
  else
    git -C "$REPO_DIR" config --local core.hooksPath "$HOOKS_DIR_NOME"
    echo "core.hooksPath: '${ATUAL:-não definido}' -> $HOOKS_DIR_NOME"
  fi
  for h in "$REPO_DIR/$HOOKS_DIR_NOME"/*; do
    [ -f "$h" ] || continue
    if [ ! -x "$h" ]; then
      chmod +x "$h"
      echo "chmod +x $(basename "$h")"
    fi
  done
else
  if [ "$ATUAL" = "$HOOKS_DIR_NOME" ]; then
    git -C "$REPO_DIR" config --local --unset core.hooksPath
    echo "core.hooksPath removido (era $HOOKS_DIR_NOME)."
  elif [ -n "$ATUAL" ]; then
    echo "core.hooksPath aponta para '$ATUAL' (não é $HOOKS_DIR_NOME); não alterado."
  else
    echo "core.hooksPath já não estava definido; nada a remover."
  fi
fi

mostrar_estado
exit 0
