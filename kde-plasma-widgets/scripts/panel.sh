#!/usr/bin/env bash
# Mexe nos widgets do Plasma pelo D-Bus (evaluateScript), sem depender de qdbus.
#
# Uso:
#   panel.sh list                         widgets de cada painel e área de trabalho (id:tipo)
#   panel.sh add <Id> [n do painel]       adiciona ao painel (padrão: 0)
#   panel.sh remove <id numérico>         remove um widget pelo id mostrado em list
#   panel.sh get <id numérico> <chave>    lê uma chave do grupo General
#   panel.sh set <id numérico> <chave> <valor>   grava e recarrega a configuração
#
# Depois de add/remove, espere uns 10 s antes de reiniciar o plasmashell: reiniciar logo em
# seguida pode deixar o widget duplicado, porque o layout ainda não foi gravado.
set -euo pipefail

js() {
  busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$1" \
    | sed -e 's/^s "//' -e 's/"$//' -e 's/\\n/\n/g'
}

# Aceita só o que cabe com segurança dentro de uma string JS.
safe() {
  case "$1" in
    *[!A-Za-z0-9._:/@#,+=\ -]*|"") echo "valor não permitido: $1" >&2; exit 2 ;;
  esac
}

FIND='function find(id){var c=panels().concat(desktops());for(var i=0;i<c.length;i++){var w=c[i].widgetById(id);if(w)return w}return null}'

cmd="${1:-}"
case "$cmd" in
  list)
    js 'var ps=panels();for(var i=0;i<ps.length;i++){print("painel "+i+": "+ps[i].widgetIds.map(function(w){return w+":"+ps[i].widgetById(w).type}).join("  ")+"\n")}
        var ds=desktops();for(var j=0;j<ds.length;j++){print("desktop "+j+": "+ds[j].widgetIds.map(function(w){return w+":"+ds[j].widgetById(w).type}).join("  ")+"\n")}'
    ;;
  add)
    safe "${2:-}"; n="${3:-0}"; case "$n" in *[!0-9]*) echo "painel inválido" >&2; exit 2 ;; esac
    js "var p=panels()[$n];if(!p){print('painel $n não existe')}else{var w=p.addWidget('$2');print('adicionado, id '+w.id)}"
    ;;
  remove)
    case "${2:-}" in *[!0-9]*|"") echo "informe o id numérico" >&2; exit 2 ;; esac
    js "$FIND;var w=find($2);if(w){w.remove();print('removido')}else{print('id $2 não encontrado')}"
    ;;
  get)
    case "${2:-}" in *[!0-9]*|"") echo "informe o id numérico" >&2; exit 2 ;; esac
    safe "${3:-}"
    js "$FIND;var w=find($2);if(w){w.currentConfigGroup=['General'];print(w.readConfig('$3',''))}else{print('id $2 não encontrado')}"
    ;;
  set)
    case "${2:-}" in *[!0-9]*|"") echo "informe o id numérico" >&2; exit 2 ;; esac
    safe "${3:-}"; safe "${4:-}"
    js "$FIND;var w=find($2);if(w){w.currentConfigGroup=['General'];w.writeConfig('$3','$4');w.reloadConfig();print('gravado')}else{print('id $2 não encontrado')}"
    ;;
  *)
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
