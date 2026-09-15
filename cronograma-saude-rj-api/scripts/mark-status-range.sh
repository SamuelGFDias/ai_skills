#!/usr/bin/env bash
# Uso: mark-status-range.sh <activityId> <startDate YYYY-MM-DD> <endDate YYYY-MM-DD> <status>
#
# Regra de negócio: o status de uma atividade no calendário é marcado por
# dia, mas quando uma atividade leva N dias corridos até ser concluída, TODOS
# os N dias do intervalo — do início até a conclusão real — recebem o MESMO
# status final. Não há estado intermediário diferente por dia dentro do
# intervalo. Ex.: se uma atividade começou hoje e levou 5 dias até ser
# concluída, os 5 dias (hoje + os 4 seguintes) são marcados com status C, não
# só o último dia.
#
# status aceita: F (A Fazer) | A (Em andamento) | C (Concluído) | "" (remove o registro do dia).
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "Uso: mark-status-range.sh <activityId> <startDate YYYY-MM-DD> <endDate YYYY-MM-DD> <status>" >&2
  echo "status: F (A Fazer) | A (Em andamento) | C (Concluído) | \"\" (remove o registro do dia)" >&2
  exit 1
fi

ACTIVITY_ID="$1"
START_DATE="$2"
END_DATE="$3"
STATUS="$4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Valida o intervalo (startDate <= endDate) e gera a lista de datas
# (inclusive nas duas pontas), sem depender de `date -d` do GNU coreutils
# (portabilidade — os demais scripts também usam python3 para isso).
DATES=$(python3 -c '
import datetime, sys

start_str, end_str = sys.argv[1], sys.argv[2]

try:
    start = datetime.date.fromisoformat(start_str)
except ValueError:
    print("Erro: startDate invalida (esperado YYYY-MM-DD): " + start_str, file=sys.stderr)
    sys.exit(1)

try:
    end = datetime.date.fromisoformat(end_str)
except ValueError:
    print("Erro: endDate invalida (esperado YYYY-MM-DD): " + end_str, file=sys.stderr)
    sys.exit(1)

if start > end:
    print("Erro: startDate (" + start_str + ") precisa ser <= endDate (" + end_str + ").", file=sys.stderr)
    sys.exit(1)

d = start
while d <= end:
    print(d.isoformat())
    d += datetime.timedelta(days=1)
' "$START_DATE" "$END_DATE")

echo "Intervalo válido: $(echo "$DATES" | wc -l) dia(s), de $START_DATE a $END_DATE, status \"$STATUS\"." >&2

while IFS= read -r DATE; do
  [[ -z "$DATE" ]] && continue
  "$SCRIPT_DIR/update-activity-day.sh" "$ACTIVITY_ID" "$DATE" "$STATUS"
done <<< "$DATES"

echo "" >&2
echo "Intervalo marcado com sucesso: atividade $ACTIVITY_ID, de $START_DATE a $END_DATE, status \"$STATUS\"." >&2
