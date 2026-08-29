#!/usr/bin/env bash
# Gera os 6 agentes do arquiteto para o Claude Code em ~/.claude/agents/.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/build-agents.py" claude
