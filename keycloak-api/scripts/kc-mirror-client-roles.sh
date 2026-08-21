#!/usr/bin/env bash
# Cria no client de destino as roles que existem no client de origem e faltam no destino
# (mesmo nome de client nos dois ambientes). Idempotente — roles já existentes são puladas.
# Uso: kc-mirror-client-roles.sh <sourceCredAlias> <targetCredAlias> <clientIdName>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SRC_ALIAS="${1:?uso: kc-mirror-client-roles.sh <sourceCredAlias> <targetCredAlias> <clientIdName>}"
TGT_ALIAS="${2:?}"
CLIENT_NAME="${3:?}"

SRC_JSON="$("$SCRIPT_DIR/kc-client-roles.sh" "$SRC_ALIAS" "$CLIENT_NAME")"
TGT_JSON="$("$SCRIPT_DIR/kc-client-roles.sh" "$TGT_ALIAS" "$CLIENT_NAME")"

TMP="$(mktemp)"
python3 -c "
import json, sys
src = json.loads(sys.argv[1])
tgt = json.loads(sys.argv[2])
tgt_names = {r['name'] for r in tgt}
missing = [r for r in src if r['name'] not in tgt_names]
print(json.dumps(missing))
" "$SRC_JSON" "$TGT_JSON" > "$TMP"

COUNT="$(python3 -c "import json; print(len(json.load(open('$TMP'))))")"

if [ "$COUNT" = "0" ]; then
  echo "client '${CLIENT_NAME}': já em paridade, nada a criar."
  rm -f "$TMP"
  exit 0
fi

echo "client '${CLIENT_NAME}': criando ${COUNT} role(s) em ${TGT_ALIAS}..."
python3 -c "
import json
for r in json.load(open('$TMP')):
    print(r['name'] + '\t' + (r.get('description') or ''))
" | while IFS=$'\t' read -r name desc; do
  "$SCRIPT_DIR/kc-create-client-role.sh" "$TGT_ALIAS" "$CLIENT_NAME" "$name" "$desc"
done

rm -f "$TMP"
