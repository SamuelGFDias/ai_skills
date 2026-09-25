#!/usr/bin/env python3
"""Helper de export-wiki.sh (não é chamado diretamente).

Dado um clone raso do repositório git por trás de uma wiki do Azure DevOps, copia as páginas
.md cujo caminho bate com o prefixo pedido para <destino>/docs/, baixa os anexos referenciados
(pasta .attachments do repo) para <destino>/assets/ e reescreve os links do markdown para
apontar pra lá.

Uso: export_wiki_helper.py <repo-clonado> <prefixo-do-path> <destino>
"""
import re
import shutil
import sys
import unicodedata
from pathlib import Path

LINK_RE = re.compile(r"(!?\[[^\]]*\]\()([^)]*\.attachments/([^)]+))(\))")


def normalize(s: str) -> str:
    """Achata acento/maiúscula/espaço~hífen para comparar path pedido com nome de arquivo —
    o Azure DevOps normaliza o título da página pro nome do arquivo, então a correspondência
    exata de string falha para títulos com acento/espaço."""
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = s.lower().replace(" ", "-").replace("_", "-")
    return re.sub(r"-+", "-", s).strip("-/")


def main():
    repo_dir, prefix, dest = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
    norm_prefix = normalize(prefix)

    all_md = sorted(p for p in repo_dir.rglob("*.md") if ".git" not in p.parts)
    matched = [p for p in all_md if normalize(str(p.relative_to(repo_dir))).startswith(norm_prefix)]

    if not matched:
        print(f"Nenhuma página encontrada sob '{prefix}'. Páginas disponíveis no repositório:")
        for p in all_md:
            print(f"  {p.relative_to(repo_dir)}")
        sys.exit(1)

    attach_dir = repo_dir / ".attachments"
    docs_dir = dest / "docs"
    assets_dir = dest / "assets"
    docs_dir.mkdir(parents=True, exist_ok=True)
    assets_dir.mkdir(parents=True, exist_ok=True)

    exported, downloaded = [], set()
    for src in matched:
        rel = src.relative_to(repo_dir)
        out_path = docs_dir / rel
        out_path.parent.mkdir(parents=True, exist_ok=True)
        content = src.read_text(encoding="utf-8", errors="replace")
        depth = len(rel.parts) - 1

        def repl(m):
            filename = Path(m.group(3)).name
            source_file = attach_dir / filename
            if source_file.exists():
                shutil.copy2(source_file, assets_dir / filename)
                downloaded.add(filename)
            new_rel = ("../" * depth) + "assets/" + filename
            return f"{m.group(1)}{new_rel}{m.group(4)}"

        content = LINK_RE.sub(repl, content)
        out_path.write_text(content, encoding="utf-8")
        exported.append(str(rel))

    print(f"{len(exported)} página(s) exportada(s) para {docs_dir}:")
    for e in exported:
        print(f"  {e}")
    print(f"{len(downloaded)} anexo(s) baixado(s) para {assets_dir}.")


if __name__ == "__main__":
    main()
