#!/usr/bin/env python3
"""Helper de export-workitems.sh (não é chamado diretamente).

Lê os JSONs de work items já baixados (um arquivo <id>.json por item, gerados pelo script
chamador via `ado_get`), converte Description/AcceptanceCriteria de HTML para markdown
(html_md.py: listas aninhadas com numeração a./i./1., negrito, tabelas), baixa as imagens referenciadas (anexos do work item, autenticados) para
<destino>/assets/, reescreve os links para apontar pra lá, e grava um .md por item na mesma
hierarquia de pastas do Azure DevOps (<destino>/<Epic>/<Feature>/<id>-<slug>.md; com ADO_STRIP_EPIC=<id> a pasta desse Epic é omitida), seguindo a
cadeia System.Parent buscada na API. Item sem pai vai para <destino>/Sem Feature/.

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

sys.path.insert(0, str(Path(__file__).resolve().parent))
from html_md import html_to_markdown  # noqa: E402

IMG_RE = re.compile(r'<img[^>]+src="([^"]+)"[^>]*/?>', re.IGNORECASE)


def slugify(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-zA-Z0-9]+", "-", s).strip("-").lower()
    return s or "item"


def download_attachment(url, dest_path, pat):
    req = urllib.request.Request(url)
    token = base64.b64encode(f":{pat}".encode()).decode()
    req.add_header("Authorization", f"Basic {token}")
    with urllib.request.urlopen(req) as resp, open(dest_path, "wb") as out:
        out.write(resp.read())


def folder_name(title: str) -> str:
    t = re.sub(r'[\\/:*?"<>|\x00-\x1f]+', "-", title).strip().strip(".")
    return re.sub(r"\s+", " ", t)[:80] or "sem-titulo"


def fetch_batch(base_url, ids, pat):
    """Campos de hierarquia via workitemsbatch (o GET simples não traz System.Parent em fields)."""
    token = base64.b64encode(f":{pat}".encode()).decode()
    out, ids = {}, list(ids)
    for k in range(0, len(ids), 200):
        body = json.dumps({"ids": ids[k:k + 200],
                           "fields": ["System.Id", "System.Title", "System.WorkItemType", "System.Parent"]})
        req = urllib.request.Request(
            f"{base_url}/_apis/wit/workitemsbatch?api-version=7.1", data=body.encode(),
            headers={"Authorization": f"Basic {token}", "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            for it in json.load(resp)["value"]:
                out[it["id"]] = it["fields"]
    return out


def resolve_ancestors(items, base_url, pat):
    """items: {id: fields dos exportados}. Preenche System.Parent e acrescenta Features/Epics."""
    items.update(fetch_batch(base_url, list(items), pat))
    todo = {f.get("System.Parent") for f in items.values()} - {None}
    while todo := todo - set(items):
        items.update(fetch_batch(base_url, todo, pat))
        todo = {f.get("System.Parent") for f in items.values()} - {None}


def folder_names(items):
    """Nome de pasta por container (não-US); irmãos com o mesmo título ganham o id no nome."""
    siblings = {}
    for i, f in items.items():
        siblings.setdefault(f.get("System.Parent"), []).append(i)
    names = {}
    for ids in siblings.values():
        counts = {}
        for i in ids:
            counts[folder_name(items[i]["System.Title"])] = counts.get(folder_name(items[i]["System.Title"]), 0) + 1
        for i in ids:
            n = folder_name(items[i]["System.Title"])
            names[i] = f"{n} ({i})" if counts[n] > 1 else n
    return names


def attachment_filename(item_id, src, seen_count):
    qs = parse_qs(urlparse(src).query)
    original = qs.get("fileName", [f"anexo-{seen_count}"])[0]
    original = re.sub(r"[^A-Za-z0-9._-]+", "-", original)
    return f"{item_id}-{original}"


def main():
    json_dir, dest, base_url = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    pat = os.environ.get("ADO_PAT", "")
    strip_epic = int(os.environ.get("ADO_STRIP_EPIC") or 0)
    docs_layout = os.environ.get("ADO_LAYOUT") == "docs"  # md em <dest>/docs/, assets em <dest>/assets/
    dry_run = os.environ.get("ADO_DRY_RUN") == "1"
    clean = os.environ.get("ADO_CLEAN") == "1"
    own_host = urlparse(base_url).path.strip("/").split("/")[0]  # organização do apelido
    assets_dir = dest / "assets"
    manifest_path = dest / ".ado-export.json"

    json_files = sorted(json_dir.glob("*.json"))
    tree_items = {}
    for jf in json_files:
        d = json.loads(jf.read_text(encoding="utf-8"))
        if "fields" in d:
            tree_items[int(d["id"])] = d["fields"]
    exported_ids = set(tree_items)
    resolve_ancestors(tree_items, base_url, pat)
    names = folder_names(tree_items)

    if not dry_run:
        dest.mkdir(parents=True, exist_ok=True)
        assets_dir.mkdir(parents=True, exist_ok=True)

    written, downloaded, failures = [], set(), []
    per_folder, n_images = {}, 0

    for json_file in json_files:
        data = json.loads(json_file.read_text(encoding="utf-8"))
        if "fields" not in data:
            print(f"Aviso: {json_file.name} sem 'fields' (erro da API?) — pulando.", file=sys.stderr)
            continue
        f = data["fields"]
        item_id = data.get("id", json_file.stem)
        title = f.get("System.Title", f"Item {item_id}")
        assigned = f.get("System.AssignedTo")
        assigned_name = assigned.get("displayName", "-") if isinstance(assigned, dict) else "-"

        parts, parent = [], tree_items[int(item_id)].get("System.Parent")
        while parent:
            parts.append(names[parent])
            parent = tree_items[parent].get("System.Parent")
        parts = parts[::-1]
        if strip_epic and parts and names[strip_epic] == parts[0]:
            parts = parts[1:]  # --epic: o destino já é o Epic, sem a pasta dele
        elif not parts:
            parts = ["Sem Feature"]
        rel_parts = (["docs"] if docs_layout else []) + parts
        item_dir = dest.joinpath(*rel_parts)
        assets_rel = "../" * len(rel_parts) + "assets"

        image_map = {}
        for field_name in ("System.Description", "Microsoft.VSTS.Common.AcceptanceCriteria"):
            raw = f.get(field_name) or ""
            for m in IMG_RE.finditer(raw):
                src = html.unescape(m.group(1))
                if src in image_map:
                    continue
                n_images += 1
                filename = attachment_filename(item_id, src, len(image_map) + 1)
                if dry_run:
                    image_map[src] = f"{assets_rel}/{filename}"
                    continue
                try:
                    download_attachment(src, assets_dir / filename, pat)
                    image_map[src] = f"{assets_rel}/{filename}"
                    downloaded.add(filename)
                except Exception as exc:
                    host = urlparse(src).path.strip("/").split("/")[0]
                    motivo = (f"anexo de outra organização ({host}), PAT de {own_host} sem acesso"
                              if host and host != own_host else str(exc))
                    failures.append((item_id, motivo))

        per_folder[" / ".join(rel_parts) or "."] = per_folder.get(" / ".join(rel_parts) or ".", 0) + 1
        if dry_run:
            continue

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
        item_dir.mkdir(parents=True, exist_ok=True)
        out = item_dir / f"{item_id}-{slugify(title)}.md"
        out.write_text("\n".join(body), encoding="utf-8")
        written.append(out)

    if dry_run:
        print(f"[dry-run] {sum(per_folder.values())} item(ns), ~{n_images} imagem(ns), nada gravado em {dest}:")
        for folder in sorted(per_folder):
            print(f"  {folder}/  ({per_folder[folder]})")
        return

    # --clean: remove o que a exportação anterior gravou e esta não regravou (renomeadas/movidas)
    new_files = {str(p.relative_to(dest)) for p in written} | {f"assets/{n}" for n in downloaded}
    if clean and manifest_path.exists():
        removed = 0
        for old in json.loads(manifest_path.read_text(encoding="utf-8")).get("files", []):
            if old not in new_files and (dest / old).is_file():
                (dest / old).unlink()
                removed += 1
        for d in sorted((p for p in dest.rglob("*") if p.is_dir()), key=lambda p: len(p.parts), reverse=True):
            if not any(d.iterdir()):
                d.rmdir()
        print(f"--clean: {removed} arquivo(s) obsoleto(s) removido(s).")
    manifest_path.write_text(json.dumps({"files": sorted(new_files)}, ensure_ascii=False, indent=1), encoding="utf-8")

    # validação: todo link de imagem local gravado precisa apontar para um arquivo existente
    link_re = re.compile(r"!\[[^\]]*\]\(([^)\s]+)\)")
    total_links, broken = 0, []
    for md in written:
        for m in link_re.finditer(md.read_text(encoding="utf-8")):
            target = m.group(1)
            if target.startswith(("http://", "https://")):
                continue
            total_links += 1
            if not (md.parent / target).exists():
                broken.append(f"{md.relative_to(dest)} -> {target}")

    print(f"{len(written)} item(ns) exportado(s) para {dest}.")
    print(f"{len(downloaded)} anexo(s) baixado(s) para {assets_dir}.")
    print(f"Validação: {total_links} link(s) de imagem local, {len(broken)} quebrado(s).")
    for b in broken:
        print(f"  QUEBRADO: {b}", file=sys.stderr)
    if failures:
        print(f"Aviso: {len(failures)} anexo(s) não baixado(s) (link original mantido no .md):", file=sys.stderr)
        for item_id, motivo in failures:
            print(f"  #{item_id}: {motivo}", file=sys.stderr)


if __name__ == "__main__":
    main()
