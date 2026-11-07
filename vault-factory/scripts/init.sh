#!/usr/bin/env bash
# init.sh — expõe os scripts desta skill fora do diretório de skills do Claude:
# symlink em ~/.local/bin (já no PATH) + alias no ~/.zshrc, para uso em qualquer diretório/shell.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="$(basename "$(dirname "$SCRIPT_DIR")")"
BIN_DIR="$HOME/.local/bin"
RC_FILE="$HOME/.zshrc"
MARKER="# $SKILL_NAME skill aliases"

mkdir -p "$BIN_DIR"

echo "Expondo scripts de $SCRIPT_DIR ..."

# Remove bloco de aliases anterior desta skill (só o dela, sem tocar em blocos de outras
# skills que porventura estejam logo acima/abaixo sem linha em branco entre eles).
if [ -f "$RC_FILE" ] && grep -qF "$MARKER" "$RC_FILE"; then
  tmp_rc="$(mktemp)"
  awk -v marker="$MARKER" '
    $0 == marker { skip=1; next }
    skip {
      if ($0 ~ /^alias /) next
      skip=0
    }
    { print }
  ' "$RC_FILE" > "$tmp_rc"
  mv "$tmp_rc" "$RC_FILE"
fi

{
  echo ""
  echo "$MARKER"
} >> "$RC_FILE"

# Todo *.sh fica executável, mesmo o que não for exposto (scripts internos chamados via exec
# por um wrapper, ex: kc.sh delegando para kc-token.sh).
for script in "$SCRIPT_DIR"/*.sh; do
  chmod +x "$script"
done

# Por padrão expõe (symlink + alias) todo *.sh da pasta. Se existir scripts/.expose, só os nomes
# listados nele (um por linha, sem .sh) são expostos — usado quando a skill tem um CLI único
# (ex: kc.sh) que já delega para os scripts individuais, e só o CLI deve virar comando de shell.
EXPOSE_FILE="$SCRIPT_DIR/.expose"
if [ -f "$EXPOSE_FILE" ]; then
  mapfile -t TO_EXPOSE < <(grep -v '^\s*#' "$EXPOSE_FILE" | grep -v '^\s*$')
else
  TO_EXPOSE=()
  for script in "$SCRIPT_DIR"/*.sh; do
    name="$(basename "$script" .sh)"
    [ "$name" = "init" ] && continue
    TO_EXPOSE+=("$name")
  done
fi

# vault-read é a interface principal da skill: sempre exposto, mesmo com .expose listando só o pb.
case " ${TO_EXPOSE[*]} " in
  *" vault-read "*) ;;
  *) TO_EXPOSE+=("vault-read") ;;
esac

for name in "${TO_EXPOSE[@]}"; do
  script="$SCRIPT_DIR/$name.sh"
  if [ ! -f "$script" ]; then
    echo "  AVISO: $EXPOSE_FILE lista '$name' mas $script não existe — pulando." >&2
    continue
  fi

  ln -sf "$script" "$BIN_DIR/$name"
  echo "  symlink: $BIN_DIR/$name -> $script"

  echo "alias $name=\"$script\"" >> "$RC_FILE"
  echo "  alias:   $name (em $RC_FILE)"
done

echo
echo "Feito. Rode 'source ~/.zshrc' ou abra um novo terminal para usar os comandos."
