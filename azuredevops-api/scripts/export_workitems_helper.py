#!/usr/bin/env python3
"""Helper de export-workitems.sh (não é chamado diretamente).

Lê os JSONs de work items já baixados (um arquivo <id>.json por item, gerados pelo script
chamador via `ado_get`), converte Description/AcceptanceCriteria de HTML para um texto
markdown simples, baixa as imagens referenciadas (anexos do work item, autenticados) para
<destino>/assets/, reescreve os links para apontar pra lá, e grava um .md por item em
<destino>/docs/.

Uso: export_workitems_helper.py <pasta-com-jsons> <destino> <base-url>
Lê o PAT da variável de ambiente ADO_PAT (nunca como argumento, para não aparecer em `ps`).
"""
import base64
import html
import json
import os
import re
import sys
import unicodedata
import urllib.request
from pathlib import Path
from urllib.parse import parse_qs, urlparse

IMG_RE = re.compile(r'<img[^>]+src="([^"]+)"[^>]*/?>', re.IGNORECASE)


def slugify(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-zA-Z0-9]+", "-", s).strip("-").lower()
    return s or "item"


def html_to_markdown(raw, image_map):
    if not raw:
        return "(vazio)"
    text = raw

    def img_repl(m):
        src = html.unescape(m.group(1))
        local = image_map.get(src)
        return f"![]({local})" if local else f"![]({src})"

    text = IMG_RE.sub(img_repl, text)
    text = re.sub(r"(?i)<li[^>]*>", "\n- ", text)
    text = re.sub(r"(?i)<(br|/p|/div|/tr)[^>]*>", "\n", text)
    # remove tags remanescentes, preservando o "![](...)" já gerado acima
    text = re.sub(r"<(?!!\[)[^>]+>", "", text)
    text = html.unescape(text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip() or "(vazio)"


def download_attachment(url, dest_path, pat):
    req = urllib.request.Request(url)
    token = base64.b64encode(f":{pat}".encode()).decode()
    req.add_header("Authorization", f"Basic {token}")
    with urllib.request.urlopen(req) as resp, open(dest_path, "wb") as out:
        out.write(resp.read())


def attachment_filename(item_id, src, seen_count):
    qs = parse_qs(urlparse(src).query)
    original = qs.get("fileName", [f"anexo-{seen_count}"])[0]
    original = re.sub(r"[^A-Za-z0-9._-]+", "-", original)
    return f"{item_id}-{original}"


def main():
    json_dir, dest, base_url = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    pat = os.environ.get("ADO_PAT", "")
    docs_dir = dest / "docs"
    assets_dir = dest / "assets"
    docs_dir.mkdir(parents=True, exist_ok=True)
    assets_dir.mkdir(parents=True, exist_ok=True)

    exported, downloaded = [], set()

    for json_file in sorted(json_dir.glob("*.json")):
        data = json.loads(json_file.read_text(encoding="utf-8"))
        if "fields" not in data:
            print(f"Aviso: {json_file.name} sem 'fields' (erro da API?) — pulando.", file=sys.stderr)
            continue
        f = data["fields"]
        item_id = data.get("id", json_file.stem)
        title = f.get("System.Title", f"Item {item_id}")
        assigned = f.get("System.AssignedTo")
        assigned_name = assigned.get("displayName", "-") if isinstance(assigned, dict) else "-"

        image_map = {}
        for field_name in ("System.Description", "Microsoft.VSTS.Common.AcceptanceCriteria"):
            raw = f.get(field_name) or ""
            for m in IMG_RE.finditer(raw):
                src = html.unescape(m.group(1))
                if src in image_map:
                    continue
                filename = attachment_filename(item_id, src, len(image_map) + 1)
                try:
                    download_attachment(src, assets_dir / filename, pat)
                    image_map[src] = f"../assets/{filename}"
                    downloaded.add(filename)
                except Exception as exc:
                    print(f"Aviso: falha ao baixar anexo de #{item_id}: {exc}", file=sys.stderr)

        body = [
            f"# {title} (#{item_id})",
            f"Tipo: {f.get('System.WorkItemType', '-')}",
            f"Estado: {f.get('System.State', '-')}",
            f"Responsável: {assigned_name}",
            f"Link: {base_url}/_workitems/edit/{item_id}",
            "",
            "## Descrição",
            html_to_markdown(f.get("System.Description"), image_map),
            "",
            "## Critérios de Aceitação",
            html_to_markdown(f.get("Microsoft.VSTS.Common.AcceptanceCriteria"), image_map),
            "",
        ]

        filename = f"{item_id}-{slugify(title)}.md"
        (docs_dir / filename).write_text("\n".join(body), encoding="utf-8")
        exported.append(filename)

    print(f"{len(exported)} item(ns) exportado(s) para {docs_dir}:")
    for e in exported:
        print(f"  {e}")
    print(f"{len(downloaded)} anexo(s) baixado(s) para {assets_dir}.")


if __name__ == "__main__":
    main()
