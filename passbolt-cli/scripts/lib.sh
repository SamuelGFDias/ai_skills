#!/usr/bin/env bash
# lib.sh — funções compartilhadas pelos scripts pb-*. Não é um comando; use `source`.

UUID_REGEX='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

# resolve_resource_id <id-ou-nome>
# Se o argumento já é um UUID, ecoa ele mesmo (stdout). Caso contrário, busca por nome
# (substring, case-insensitive) via `passbolt list resources --json`:
#   - 1 resultado  -> ecoa o ID em stdout e avisa em stderr qual recurso foi resolvido.
#   - 0 resultados -> erro em stderr, retorno 1.
#   - >1 resultados -> lista candidatos (nome + id) em stderr, retorno 1 — usuário refina ou usa o ID.
resolve_resource_id() {
  local query="$1"

  if [[ "$query" =~ $UUID_REGEX ]]; then
    echo "$query"
    return 0
  fi

  if ! command -v passbolt &>/dev/null; then
    echo "ERRO: passbolt (go-passbolt-cli) não está instalado ou fora do PATH." >&2
    return 1
  fi
  if ! command -v jq &>/dev/null; then
    echo "ERRO: jq não está instalado." >&2
    return 1
  fi

  local list_json
  if ! list_json="$(passbolt list resources --json)"; then
    echo "ERRO: falha ao listar recursos do Passbolt." >&2
    return 1
  fi

  local matches count
  matches="$(jq -c --arg q "${query,,}" '
      [.[] | select(((.name // .Name // "") | ascii_downcase) | contains($q))
       | {id: (.id // .ID), name: (.name // .Name)}]
    ' <<<"$list_json")"
  count="$(jq 'length' <<<"$matches")"

  if [ "$count" -eq 0 ]; then
    echo "ERRO: nenhum recurso encontrado com nome contendo \"$query\"." >&2
    return 1
  fi

  if [ "$count" -gt 1 ]; then
    echo "ERRO: mais de um recurso encontrado com nome contendo \"$query\":" >&2
    jq -r '.[] | "  - \(.name)  [\(.id)]"' <<<"$matches" >&2
    echo "Refine o termo de busca ou use o ID diretamente." >&2
    return 1
  fi

  local resolved_id resolved_name
  resolved_id="$(jq -r '.[0].id' <<<"$matches")"
  resolved_name="$(jq -r '.[0].name' <<<"$matches")"
  echo "Recurso resolvido por nome: \"$resolved_name\" -> $resolved_id" >&2

  echo "$resolved_id"
}
