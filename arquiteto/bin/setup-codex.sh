#!/usr/bin/env bash
# Gera os 6 agentes do arquiteto para o Codex em ~/.codex/agents/.
# Antes de rodar, ajuste cli/codex/models.json aos modelos OpenAI do time.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/build-agents.py" codex
