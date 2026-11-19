#!/usr/bin/env bash
# Abre o widget numa janela e salva uma captura, para conferir o visual sem clicar no painel.
#
# Uso: preview.sh <Id> <saida.png> [segundos de espera, padrão 8]
# Precisa de plasmawindowed e spectacle. Mostra a representação completa (o menu).
# A captura é da janela ATIVA: se o usuário estiver usando outra janela, sai a janela errada.
# Sempre abra a imagem e confira que é o widget antes de tirar conclusões.
set -euo pipefail

if [ $# -lt 2 ]; then
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi
id="$1"; out="$2"; wait="${3:-8}"
for c in plasmawindowed spectacle; do
  command -v "$c" >/dev/null 2>&1 || { echo "falta o comando $c" >&2; exit 1; }
done

log="$(mktemp)"
timeout "$((wait + 6))" plasmawindowed "$id" >"$log" 2>&1 &
sleep "$wait"
spectacle -b -n -a -o "$out" >/dev/null 2>&1 || true
sleep 1
grep -i -E "error|TypeError|ReferenceError" "$log" | head -10 || true
rm -f "$log"
[ -s "$out" ] && echo "Captura da janela ativa: $out (confira se é mesmo o widget)" || { echo "Não consegui capturar (a janela pode não ter ganhado o foco)" >&2; exit 1; }
