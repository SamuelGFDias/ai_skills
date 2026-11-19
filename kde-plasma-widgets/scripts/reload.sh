#!/usr/bin/env bash
# Confere o QML, recarrega o plasmashell e mostra os erros do widget.
#
# Uso: reload.sh <Id> [pasta do widget] [--no-restart]
# Sem a pasta, usa a instalada em ~/.local/share/plasma/plasmoids/<Id>.
set -uo pipefail

if [ $# -lt 1 ]; then
  sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

id="$1"; shift
dir="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$id"; restart=1
for arg in "$@"; do
  case "$arg" in
    --no-restart) restart=0 ;;
    *) dir="$arg" ;;
  esac
done
[ -d "$dir/contents/ui" ] || { echo "Não achei $dir/contents/ui" >&2; exit 1; }

# qmllint muda de nome e de lugar conforme a distro.
lint=""
for c in qmllint6 qmllint-qt6 /usr/lib64/qt6/bin/qmllint /usr/lib/qt6/bin/qmllint qmllint; do
  if command -v "$c" >/dev/null 2>&1; then lint="$c"; break; fi
done
status=0
if [ -n "$lint" ]; then
  qmldir=""
  for q in /usr/lib64/qt6/qml /usr/lib/qt6/qml /usr/lib/x86_64-linux-gnu/qt6/qml; do
    [ -d "$q" ] && { qmldir="$q"; break; }
  done
  # "Unqualified access" e ListView.onAdd/onRemove são ruído conhecido do qmllint.
  out="$("$lint" ${qmldir:+-I "$qmldir"} "$dir"/contents/ui/*.qml 2>&1 \
        | grep -E '^(Error|Warning)' | grep -v -E 'Unqualified|"onAdd"|"onRemove"' || true)"
  if [ -n "$out" ]; then
    echo "== qmllint"; echo "$out"
    echo "$out" | grep -q '^Error' && status=1
  else
    echo "== qmllint: sem erros"
  fi
else
  echo "== qmllint não encontrado (pacote qt6-qtdeclarative-devel ou qt6-declarative-dev-tools)"
fi
if [ "$status" -ne 0 ]; then
  echo "Corrija os erros antes de recarregar." >&2
  exit 1
fi

[ "$restart" -eq 1 ] || exit 0

since="$(date '+%Y-%m-%d %H:%M:%S')"
systemctl --user restart plasma-plasmashell
for _ in $(seq 1 30); do
  sleep 1
  busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s 'print(1)' >/dev/null 2>&1 && break
done
sleep 5  # tempo para o widget carregar e fazer a primeira consulta
echo "== plasmashell: $(systemctl --user is-active plasma-plasmashell)"

files="$(cd "$dir/contents/ui" && ls *.qml | tr '\n' '|')"
log="$(journalctl --user -u plasma-plasmashell --since "$since" --no-pager 2>/dev/null \
      | grep -E "${id}|${files}TypeError|ReferenceError" || true)"
if [ -n "$log" ]; then echo "== erros no log"; echo "$log" | head -20; else echo "== log: nada sobre o widget"; fi

rc="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
if [ -f "$rc" ]; then
  n="$(grep -c "^plugin=${id}\$" "$rc" || true)"
  echo "== instâncias no layout: $n"
  [ "$n" -gt 1 ] && echo "AVISO: widget duplicado. Liste com panel.sh list e remova o extra com panel.sh remove <n>."
fi
exit 0
