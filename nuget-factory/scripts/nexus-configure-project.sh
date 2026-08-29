#!/usr/bin/env bash
# Gera/atualiza o NuGet.Config de um projeto .NET apontando para o Nexus SES,
# seguindo a convencao validada: source de consumo (nuget-group) e,
# opcionalmente, source de publicacao (nuget-hosted). Senha nunca em texto claro
# no arquivo -- resolvida via variavel de ambiente %NEXUS_NUGET_PASSWORD%.
#
# Uso:
#   nexus-configure-project.sh <diretorio-do-projeto> [--hosted]
#
#   --hosted   tambem adiciona a source "nexus-ses-hosted" (nuget-hosted), usada
#              para "dotnet nuget push". Sem essa flag, so a source de consumo
#              (nuget-group) e criada.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"

PROJETO_DIR="${1:?Uso: nexus-configure-project.sh <diretorio-do-projeto> [--hosted]}"
INCLUIR_HOSTED="false"
[[ "${2:-}" == "--hosted" ]] && INCLUIR_HOSTED="true"

[[ -d "$PROJETO_DIR" ]] || { echo "Diretorio nao existe: $PROJETO_DIR" >&2; exit 1; }

CONFIG_PATH="$PROJETO_DIR/NuGet.Config"

if [[ -f "$CONFIG_PATH" ]]; then
  read -r -p "NuGet.Config ja existe em '$CONFIG_PATH'. Sobrescrever? [y/N] " resp
  [[ "$resp" =~ ^[Yy]$ ]] || { echo "Cancelado."; exit 0; }
fi

{
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<configuration>'
  echo '  <packageSources>'
  echo '    <clear />'
  echo "    <add key=\"nexus-ses\" value=\"${NEXUS_HOST}/repository/nuget-group/index.json\" />"
  if [[ "$INCLUIR_HOSTED" == "true" ]]; then
    echo "    <add key=\"nexus-ses-hosted\" value=\"${NEXUS_HOST}/repository/nuget-hosted/\" />"
  fi
  echo '  </packageSources>'
  echo '  <packageSourceCredentials>'
  echo '    <nexus-ses>'
  echo "      <add key=\"Username\" value=\"${NEXUS_USER}\" />"
  echo '      <add key="ClearTextPassword" value="%NEXUS_NUGET_PASSWORD%" />'
  echo '    </nexus-ses>'
  if [[ "$INCLUIR_HOSTED" == "true" ]]; then
    echo '    <nexus-ses-hosted>'
    echo "      <add key=\"Username\" value=\"${NEXUS_USER}\" />"
    echo '      <add key="ClearTextPassword" value="%NEXUS_NUGET_PASSWORD%" />'
    echo '    </nexus-ses-hosted>'
  fi
  echo '  </packageSourceCredentials>'
  echo '</configuration>'
} > "$CONFIG_PATH"

echo "OK: $CONFIG_PATH gerado."
echo
echo "Antes de rodar dotnet restore/add package/push, exporte a senha (sem ecoa-la):"
echo '  export NEXUS_PASSWORD=passbolt://'"$NEXUS_PASSBOLT_RESOURCE_ID"
echo '  passbolt exec -- bash -c '"'"'export NEXUS_NUGET_PASSWORD="$NEXUS_PASSWORD"; dotnet restore'"'"
