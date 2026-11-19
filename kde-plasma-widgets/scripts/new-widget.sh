#!/usr/bin/env bash
# Cria um widget do Plasma 6 a partir do modelo desta skill.
#
# Uso: new-widget.sh <Id> "<Nome>" [diretório de destino] [--link]
#   Id     ex.: org.exemplo.meuwidget (vira o nome da pasta)
#   --link cria o symlink em ~/.local/share/plasma/plasmoids/<Id> para desenvolver sem reinstalar
set -euo pipefail

if [ $# -lt 2 ]; then
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

id="$1"; name="$2"; shift 2
dest_dir="."; link=0
for arg in "$@"; do
  case "$arg" in
    --link) link=1 ;;
    *) dest_dir="$arg" ;;
  esac
done

case "$id" in
  *[!A-Za-z0-9._-]*|"") echo "Id inválido: use letras, números, ponto, hífen e sublinhado" >&2; exit 2 ;;
esac

template="$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates/widget" && pwd)"
target="$dest_dir/$id"
if [ -e "$target" ]; then
  echo "Já existe: $target" >&2
  exit 1
fi

mkdir -p "$dest_dir"
cp -r "$template" "$target"

author="$(git config user.name 2>/dev/null || true)"
[ -n "$author" ] || author="${USER:-autor}"

# Substitui os marcadores sem depender de sed com delimitador (o nome pode ter qualquer caractere).
ID="$id" NAME="$name" AUTHOR="$author" python3 - "$target" <<'PY'
import os, sys
root = sys.argv[1]
subs = {"__ID__": os.environ["ID"], "__NAME__": os.environ["NAME"], "__AUTHOR__": os.environ["AUTHOR"]}
for base, _dirs, files in os.walk(root):
    for f in files:
        path = os.path.join(base, f)
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        new = text
        for k, v in subs.items():
            # dentro do JSON e do Python o valor entra em uma string: escapa aspas e barras
            new = new.replace(k, v.replace("\\", "\\\\").replace('"', '\\"'))
        if new != text:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(new)
PY
chmod +x "$target/contents/code/bridge.py"

echo "Criado: $target"
if [ "$link" -eq 1 ]; then
  plasmoids="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids"
  mkdir -p "$plasmoids"
  ln -sfn "$(cd "$target" && pwd)" "$plasmoids/$id"
  echo "Symlink: $plasmoids/$id"
fi
echo "Próximo passo: plasmawindowed $id   (precisa do symlink ou de kpackagetool6 --install)"
