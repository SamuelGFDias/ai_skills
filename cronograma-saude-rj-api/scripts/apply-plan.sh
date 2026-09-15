#!/usr/bin/env bash
# Uso: apply-plan.sh <projectId> <plan.json> [--dry-run]
#
# Aplica um "plano" (categorias + atividades, com notes opcionais) de uma vez,
# reaproveitando create-category.sh / create-activity.sh / update-notes.sh na
# mesma ordem usada manualmente (notes sempre depois da criação da atividade —
# ver armadilha do PUT /activities/{id} documentada no SKILL.md).
#
# Schema de plan.json:
# {
#   "categories": [
#     {
#       "name": "Nome da categoria",
#       "activities": [
#         { "number": 1, "description": "Descrição da atividade", "notes": "Observação opcional" }
#       ]
#     }
#   ]
# }
#
# --dry-run: só valida o plan.json e imprime uma prévia; nenhuma chamada de
# escrita (POST/PATCH/PUT) é feita à API.
#
# Sem --dry-run: cria categorias e atividades na ordem do plano. Se algo falhar
# no meio do lote, para imediatamente, imprime em stderr o que já foi criado
# com sucesso (para permitir limpeza manual) e sai com código != 0. Não faz
# rollback automático.
#
# Em caso de sucesso total, imprime em stdout um resumo JSON com os ids
# criados (categorias e atividades).
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Uso: apply-plan.sh <projectId> <plan.json> [--dry-run]" >&2
  exit 1
fi

PROJECT_ID="$1"
PLAN_FILE="$2"
DRY_RUN=0
for arg in "${@:3}"; do
  if [[ "$arg" == "--dry-run" ]]; then
    DRY_RUN=1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Validação + normalização do plano (não toca a API) ---------------------
# Emite uma linha JSON por categoria, já normalizada (notes ausente/null vira
# ""), ou falha com mensagem clara em stderr e exit != 0 sem chamar a API.
VALIDATE_PY='
import json, sys

path = sys.argv[1]
try:
    with open(path) as f:
        plan = json.load(f)
except FileNotFoundError:
    print(f"Erro: arquivo de plano não encontrado: {path}", file=sys.stderr)
    sys.exit(1)
except json.JSONDecodeError as e:
    print(f"Erro: JSON inválido em {path}: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(plan, dict):
    print("Erro: plano precisa ser um objeto JSON.", file=sys.stderr)
    sys.exit(1)

categories = plan.get("categories")
if not isinstance(categories, list) or len(categories) == 0:
    print("Erro: plano precisa ter \"categories\" como lista não vazia.", file=sys.stderr)
    sys.exit(1)

normalized = []
for ci, cat in enumerate(categories):
    if not isinstance(cat, dict):
        print(f"Erro: categories[{ci}] precisa ser um objeto.", file=sys.stderr)
        sys.exit(1)
    name = cat.get("name")
    if not isinstance(name, str) or not name.strip():
        print(f"Erro: categories[{ci}].name é obrigatório (string não vazia).", file=sys.stderr)
        sys.exit(1)
    activities = cat.get("activities", [])
    if not isinstance(activities, list):
        print(f"Erro: categories[{ci}].activities precisa ser uma lista.", file=sys.stderr)
        sys.exit(1)
    norm_activities = []
    for ai, act in enumerate(activities):
        if not isinstance(act, dict):
            print(f"Erro: categories[{ci}].activities[{ai}] precisa ser um objeto.", file=sys.stderr)
            sys.exit(1)
        number = act.get("number")
        if not isinstance(number, int) or isinstance(number, bool):
            print(f"Erro: categories[{ci}].activities[{ai}].number é obrigatório (inteiro).", file=sys.stderr)
            sys.exit(1)
        description = act.get("description")
        if not isinstance(description, str) or not description.strip():
            print(f"Erro: categories[{ci}].activities[{ai}].description é obrigatório (string não vazia).", file=sys.stderr)
            sys.exit(1)
        notes = act.get("notes", "")
        if notes is None:
            notes = ""
        if not isinstance(notes, str):
            print(f"Erro: categories[{ci}].activities[{ai}].notes precisa ser string.", file=sys.stderr)
            sys.exit(1)
        norm_activities.append({"number": number, "description": description, "notes": notes})
    normalized.append({"name": name, "activities": norm_activities})

for cat in normalized:
    print(json.dumps(cat, ensure_ascii=False))
'

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "Erro: arquivo de plano não encontrado: $PLAN_FILE" >&2
  exit 1
fi

CATEGORIES_JSONL=$(python3 -c "$VALIDATE_PY" "$PLAN_FILE")

echo "Plano válido: $(echo "$CATEGORIES_JSONL" | wc -l) categoria(s)." >&2

# --- Modo --dry-run: só prévia, nenhuma chamada de escrita -------------------
if [[ "$DRY_RUN" -eq 1 ]]; then
  PREVIEW_PY='
import json, sys

for i, line in enumerate(sys.stdin, start=1):
    line = line.strip()
    if not line:
        continue
    cat = json.loads(line)
    name = cat["name"]
    activities = cat["activities"]
    print("[DRY-RUN] Categoria %d: \"%s\" (%d atividade(s))" % (i, name, len(activities)))
    for act in activities:
        number = act["number"]
        description = act["description"]
        notes = act["notes"]
        if notes:
            notes_info = " | notes: \"%s\"" % notes
        else:
            notes_info = " | notes: (não seta)"
        print("  - #%s: %s%s" % (number, description, notes_info))
print("[DRY-RUN] Nenhuma chamada de escrita (POST/PATCH/PUT) foi feita à API.")
'
  echo "$CATEGORIES_JSONL" | python3 -c "$PREVIEW_PY"
  exit 0
fi

# --- Execução real ------------------------------------------------------------
EVENTS_LOG=$(mktemp)
trap 'rm -f "$EVENTS_LOG"' EXIT

SUMMARIZE_PY='
import json, sys

events_path, project_id = sys.argv[1], sys.argv[2]
categories = []
by_cat_id = {}
with open(events_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        ev = json.loads(line)
        if ev["type"] == "category":
            cat = {"name": ev["name"], "id": ev["id"], "activities": []}
            categories.append(cat)
            by_cat_id[ev["id"]] = cat
        elif ev["type"] == "activity":
            cat = by_cat_id.get(ev["categoryId"])
            if cat is None:
                continue
            cat["activities"].append({
                "number": ev["number"],
                "description": ev["description"],
                "id": ev["id"],
                "notesSet": ev["notesSet"],
            })

print(json.dumps({"projectId": project_id, "categories": categories}, indent=2, ensure_ascii=False))
'

report_and_exit() {
  echo "" >&2
  echo "=== Falha no meio do lote. Itens já criados com sucesso até este ponto (para limpeza manual): ===" >&2
  if [[ -s "$EVENTS_LOG" ]]; then
    python3 -c "$SUMMARIZE_PY" "$EVENTS_LOG" "$PROJECT_ID" >&2
  else
    echo "(nenhum item foi criado antes da falha)" >&2
  fi
  exit 1
}

while IFS= read -r CAT_JSON; do
  [[ -z "$CAT_JSON" ]] && continue

  CAT_NAME=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["name"])' "$CAT_JSON")

  echo "== Criando categoria: $CAT_NAME ==" >&2
  if ! CATEGORY_ID=$("$SCRIPT_DIR/create-category.sh" "$PROJECT_ID" "$CAT_NAME"); then
    echo "Falha ao criar categoria \"$CAT_NAME\". Abortando lote." >&2
    report_and_exit
  fi

  python3 -c 'import json,sys; print(json.dumps({"type":"category","name":sys.argv[1],"id":sys.argv[2]}, ensure_ascii=False))' \
    "$CAT_NAME" "$CATEGORY_ID" >> "$EVENTS_LOG"

  ACTIVITIES_JSONL=$(python3 -c '
import json, sys
cat = json.loads(sys.argv[1])
for act in cat["activities"]:
    print(json.dumps(act, ensure_ascii=False))
' "$CAT_JSON")

  while IFS= read -r ACT_JSON; do
    [[ -z "$ACT_JSON" ]] && continue

    ACT_NUMBER=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["number"])' "$ACT_JSON")
    ACT_DESC=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["description"])' "$ACT_JSON")
    ACT_NOTES=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["notes"])' "$ACT_JSON")

    echo "-- Criando atividade #$ACT_NUMBER: $ACT_DESC --" >&2
    if ! ACTIVITY_ID=$("$SCRIPT_DIR/create-activity.sh" "$PROJECT_ID" "$CATEGORY_ID" "$ACT_NUMBER" "$ACT_DESC"); then
      echo "Falha ao criar atividade #$ACT_NUMBER (\"$ACT_DESC\") na categoria \"$CAT_NAME\". Abortando lote." >&2
      report_and_exit
    fi

    NOTES_SET=false
    if [[ -n "$ACT_NOTES" ]]; then
      if ! "$SCRIPT_DIR/update-notes.sh" "$ACTIVITY_ID" "$ACT_NOTES" >/dev/null; then
        echo "Falha ao definir notes da atividade #$ACT_NUMBER (id $ACTIVITY_ID) na categoria \"$CAT_NAME\". Abortando lote." >&2
        report_and_exit
      fi
      NOTES_SET=true
    fi

    python3 -c 'import json,sys
print(json.dumps({
    "type": "activity",
    "categoryId": sys.argv[1],
    "number": int(sys.argv[2]),
    "description": sys.argv[3],
    "id": sys.argv[4],
    "notesSet": sys.argv[5] == "true",
}, ensure_ascii=False))
' "$CATEGORY_ID" "$ACT_NUMBER" "$ACT_DESC" "$ACTIVITY_ID" "$NOTES_SET" >> "$EVENTS_LOG"
  done <<< "$ACTIVITIES_JSONL"
done <<< "$CATEGORIES_JSONL"

echo "" >&2
echo "Lote aplicado com sucesso." >&2
python3 -c "$SUMMARIZE_PY" "$EVENTS_LOG" "$PROJECT_ID"
