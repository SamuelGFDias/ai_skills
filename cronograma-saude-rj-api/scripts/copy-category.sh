#!/usr/bin/env bash
# Uso: copy-category.sh <srcProjectId> <categoryName> <dstProjectId> [--months YYYY-MM[,YYYY-MM...]] [--dry-run]
#
# Copia uma categoria inteira de um projeto para outro: a categoria, suas
# atividades (descrição, responsável e notes) e os dias marcados no calendário
# (data + status). Monta um plan.json a partir do calendário do projeto de
# origem e o aplica com apply-plan.sh no projeto de destino. Não altera nem
# exclui nada na origem — para "mover", excluir a origem depois, à parte.
#
# - Numeração: a numeração das atividades é por projeto, não por categoria. As
#   atividades copiadas recebem números sequenciais a partir do maior número já
#   existente no destino (+1), mantendo a ordem relativa da origem.
# - Dias: o calendário só devolve um mês por chamada, então só são copiados os
#   dias dos meses em --months (default: o mês corrente). Dias de outros meses
#   NÃO são copiados — informe todos os meses que tiverem marcação.
# - Aborta sem criar nada se o destino já tiver uma categoria com o mesmo nome
#   (evita duplicar a categoria ao reaplicar).
# - --dry-run: valida e imprime a prévia (via apply-plan.sh --dry-run), sem
#   chamadas de escrita.
#
# Em caso de sucesso, imprime em stdout o resumo JSON do apply-plan.sh.
set -euo pipefail

USAGE="Uso: copy-category.sh <srcProjectId> <categoryName> <dstProjectId> [--months YYYY-MM[,YYYY-MM...]] [--dry-run]"

if [[ $# -lt 3 ]]; then
  echo "$USAGE" >&2
  exit 1
fi

SRC_PROJECT_ID="$1"
CATEGORY_NAME="$2"
DST_PROJECT_ID="$3"
shift 3

MONTHS=""
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --months)
      if [[ $# -lt 2 ]]; then
        echo "Erro: --months exige um valor (YYYY-MM[,YYYY-MM...])." >&2
        exit 1
      fi
      MONTHS="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *)
      echo "Erro: argumento desconhecido: $1" >&2
      echo "$USAGE" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$SRC_PROJECT_ID" ]]; then
  echo "Erro: srcProjectId não pode ser vazio." >&2
  exit 1
fi
if [[ -z "$CATEGORY_NAME" ]]; then
  echo "Erro: categoryName não pode ser vazio." >&2
  exit 1
fi
if [[ -z "$DST_PROJECT_ID" ]]; then
  echo "Erro: dstProjectId não pode ser vazio." >&2
  exit 1
fi
if [[ "$SRC_PROJECT_ID" == "$DST_PROJECT_ID" ]]; then
  echo "Erro: origem e destino são o mesmo projeto." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="https://cronograma.saude.rj.gov.br/api"
COOKIE_JAR="${CRONOGRAMA_COOKIE_JAR:-$HOME/.cache/cronograma-cookies.txt}"
mkdir -p "$(dirname "$COOKIE_JAR")"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# GET autenticado: grava o corpo em $2 e falha com a mensagem da API se != 2xx.
api_get() {
  local path="$1" out="$2" response http_code
  response=$(curl -s -w '\n%{http_code}' -b "$COOKIE_JAR" "$BASE_URL$path")
  http_code=$(echo "$response" | tail -n1)
  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "Erro em GET $path (HTTP $http_code):" >&2
    echo "$response" | sed '$d' >&2
    return 1
  fi
  echo "$response" | sed '$d' > "$out"
}

# Meses a varrer, no formato "YYYY-MM" (default: mês corrente).
MONTH_LIST=$(python3 -c '
import datetime, re, sys
raw = sys.argv[1]
if not raw:
    today = datetime.date.today()
    raw = "%04d-%02d" % (today.year, today.month)
for m in raw.split(","):
    if not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", m):
        print("Erro: mês inválido em --months (esperado YYYY-MM): " + m, file=sys.stderr)
        sys.exit(1)
    print(m)
' "$MONTHS")

echo "Meses varridos no calendário de origem: $(echo "$MONTH_LIST" | tr '\n' ' ')" >&2

# Calendário de origem, um arquivo por mês (a API usa month 0-indexado).
INDEX=0
while IFS= read -r YM; do
  [[ -z "$YM" ]] && continue
  YEAR="${YM%-*}"
  MONTH=$((10#${YM#*-} - 1))
  api_get "/calendar?projectId=$SRC_PROJECT_ID&year=$YEAR&month=$MONTH" "$WORK_DIR/cal_$INDEX.json"
  INDEX=$((INDEX + 1))
done <<< "$MONTH_LIST"

api_get "/activities?projectId=$DST_PROJECT_ID" "$WORK_DIR/dst_activities.json"
api_get "/categories?projectId=$DST_PROJECT_ID" "$WORK_DIR/dst_categories.json"

# Monta o plan.json. Falha (sem tocar a API) se a categoria de origem não existir,
# estiver vazia ou já existir no destino.
python3 - "$CATEGORY_NAME" "$WORK_DIR" > "$WORK_DIR/plan.json" <<'PY'
import glob, json, sys

category_name, work_dir = sys.argv[1], sys.argv[2]


def load(path):
    with open(path) as f:
        data = json.load(f)
    return data if isinstance(data, list) else data.get("data", data)


dst_categories = load(f"{work_dir}/dst_categories.json")
if any(c.get("name") == category_name for c in dst_categories):
    print(f"Erro: o destino já tem uma categoria \"{category_name}\". Nada foi criado.", file=sys.stderr)
    sys.exit(1)

dst_numbers = [a["number"] for a in load(f"{work_dir}/dst_activities.json")]
start = max(dst_numbers, default=0) + 1

calendars = [json.load(open(p)) for p in sorted(glob.glob(f"{work_dir}/cal_*.json"))]
category = next((c for c in calendars[0]["categories"] if c.get("name") == category_name), None)
if category is None:
    names = ", ".join(sorted(c["name"] for c in calendars[0]["categories"])) or "(nenhuma)"
    print(f"Erro: categoria \"{category_name}\" não existe na origem. Categorias: {names}", file=sys.stderr)
    sys.exit(1)

# A API devolve os campos em snake_case (category_id), não camelCase.
source = sorted((a for a in calendars[0]["activities"] if a["category_id"] == category["id"]),
                key=lambda a: a["number"])
if not source:
    print(f"Erro: a categoria \"{category_name}\" não tem atividades na origem.", file=sys.stderr)
    sys.exit(1)

# activityDays é um dicionário "<activityId>_<YYYY-MM-DD>" -> status, por mês.
days_by_activity = {}
for cal in calendars:
    for key, status in cal["activityDays"].items():
        activity_id, date = key.rsplit("_", 1)
        if status in ("F", "A", "C"):
            days_by_activity.setdefault(activity_id, []).append({"date": date, "status": status})

activities = []
for offset, act in enumerate(source):
    item = {
        "number": start + offset,
        "description": act["description"],
        "days": sorted(days_by_activity.get(act["id"], []), key=lambda d: d["date"]),
    }
    if act.get("responsible"):
        item["responsible"] = act["responsible"]
    if act.get("notes"):
        item["notes"] = act["notes"]
    activities.append(item)

print(json.dumps({"categories": [{"name": category_name, "activities": activities}]}, ensure_ascii=False))
print(f"Origem: {len(activities)} atividade(s), numeração {start}..{start + len(activities) - 1} no destino, "
      f"{sum(len(a['days']) for a in activities)} dia(s) marcado(s).", file=sys.stderr)
PY

if [[ "$DRY_RUN" -eq 1 ]]; then
  "$SCRIPT_DIR/apply-plan.sh" "$DST_PROJECT_ID" "$WORK_DIR/plan.json" --dry-run
else
  "$SCRIPT_DIR/apply-plan.sh" "$DST_PROJECT_ID" "$WORK_DIR/plan.json"
fi
