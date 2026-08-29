#!/usr/bin/env bash
# Gera os 6 agentes do arquiteto para o Kilo em ~/.config/kilo/agent/.
# Antes de rodar, ajuste cli/kilo/models.json aos modelos do seu kilo.jsonc.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/build-agents.py" kilo
