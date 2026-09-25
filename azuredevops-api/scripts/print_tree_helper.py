#!/usr/bin/env python3
"""Helper de list-tree.sh (não é chamado diretamente).

Recebe os pares pai->filho (Feature -> work item filho) e os dados batch dos ids envolvidos,
e imprime uma árvore em formato de pastas (slug do título), só para visualização — nenhum
arquivo é criado.

Uso: print_tree_helper.py <pairs.tsv> <items.json> <tipo-filho>
"""
import json
import re
import sys
import unicodedata
from collections import defaultdict


def slugify(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-zA-Z0-9]+", "-", s).strip("-").lower()
    return s or "item"


def main():
    pairs_file, items_file, child_type = sys.argv[1], sys.argv[2], sys.argv[3]

    with open(items_file, encoding="utf-8") as fh:
        data = json.load(fh)
    items = {str(it["fields"]["System.Id"]): it["fields"] for it in data.get("value", [])}

    children = defaultdict(list)
    with open(pairs_file, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            parent, child = line.split("\t")
            children[parent].append(child)

    parent_ids = sorted(
        children, key=lambda p: items.get(p, {}).get("System.Title", "")
    )
    printed_any = False
    for parent_id in parent_ids:
        parent = items.get(parent_id)
        if not parent:
            continue
        matching_children = [
            c for c in children[parent_id]
            if items.get(c, {}).get("System.WorkItemType") == child_type
        ]
        if not matching_children:
            continue
        printed_any = True
        print(f"/{slugify(parent['System.Title'])}  ({parent['System.Title']} — Feature #{parent_id}, {parent.get('System.State', '-')})")
        for child_id in sorted(matching_children, key=lambda c: items[c]["System.Title"]):
            child = items[child_id]
            slug = slugify(child["System.Title"])
            print(f"  /{slug}")
            print(f"    {slug}.md   (#{child_id} — {child.get('System.State', '-')})")

    if not printed_any:
        print(f"Nenhum item do tipo '{child_type}' encontrado como filho de alguma Feature.")


if __name__ == "__main__":
    main()
