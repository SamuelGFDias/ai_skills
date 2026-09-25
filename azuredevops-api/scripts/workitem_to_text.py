#!/usr/bin/env python3
"""Helper de get-workitem.sh (não é chamado diretamente).

Converte o JSON de um work item do Azure DevOps num texto simples, transformando os campos
Description/AcceptanceCriteria (HTML bruto, cheio de estilo inline) em texto legível.

Uso: workitem_to_text.py <arquivo-json> <base-url> <id>
"""
import html
import json
import re
import sys


def html_to_text(raw):
    if not raw:
        return "(vazio)"
    text = re.sub(r"(?i)<li[^>]*>", "\n- ", raw)
    text = re.sub(r"(?i)<(br|/p|/div|/tr)[^>]*>", "\n", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip() or "(vazio)"


def main():
    json_path, base_url, item_id = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(json_path, encoding="utf-8") as fh:
        data = json.load(fh)

    if "fields" not in data:
        print(f"Erro ao buscar #{item_id}: {data.get('message', json.dumps(data)[:300])}", file=sys.stderr)
        sys.exit(1)

    f = data["fields"]
    assigned = f.get("System.AssignedTo")
    assigned_name = assigned.get("displayName", "-") if isinstance(assigned, dict) else "-"

    print(f"# {f.get('System.Title', '(sem título)')} (#{item_id})")
    print(f"Tipo: {f.get('System.WorkItemType', '-')}")
    print(f"Estado: {f.get('System.State', '-')}")
    print(f"Responsável: {assigned_name}")
    print(f"Prioridade: {f.get('Microsoft.VSTS.Common.Priority', '-')}")
    print(f"Link: {base_url}/_workitems/edit/{item_id}")
    print()
    print("## Descrição")
    print(html_to_text(f.get("System.Description")))
    print()
    print("## Critérios de Aceitação")
    print(html_to_text(f.get("Microsoft.VSTS.Common.AcceptanceCriteria")))


if __name__ == "__main__":
    main()
