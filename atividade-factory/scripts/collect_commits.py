#!/usr/bin/env python3
"""Coleta determinística de commits de um ou mais projetos GitLab num período, por autor.

Faz só o trabalho mecânico (chamar a API, deduplicar, descartar merges triviais) para não
gastar tokens do modelo em parsing. A decisão de "o que é funcionalidade" x "fora de
escopo/config" fica para a etapa de análise (delegada por projeto), não para este script.

Uso:
    python3 collect_commits.py --since 2026-09-01 --emails a@x.com,b@y.com \
        --out-dir /caminho/workspace [--until 2026-09-30] [--projects 5,272] [--host HOST]

Sem --projects, descobre os projetos tocados no período via /events?action=pushed do
usuário autenticado.

Saída: um arquivo <out-dir>/commits/<project_id>.json por projeto com commits (deduplicados
por sha, sem merge commit trivial), mais <out-dir>/commits/_index.json com nome do projeto,
contagem e a lista de projetos sem nenhum commit do autor (para não silenciar falso-negativo).

Cada commit leva também `na_default_branch` (bool: o commit já está na branch padrão do projeto)
e `branches` (lista das branches que o contêm, via /commits/:sha/refs?type=branch), para a
elegibilidade ser decidida aqui, de forma determinística, antes do agrupamento. Se a consulta de
refs falhar para um commit, `branches` e `na_default_branch` ficam null (nunca assumir true).
"""
import argparse
import json
import os
import subprocess
from collections import Counter
from datetime import datetime, timedelta


def glab_api(path, host=None, paginate=False):
    cmd = ["glab", "api", path]
    if paginate:
        cmd.append("--paginate")
    if host:
        cmd += ["--hostname", host]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    return load_multi_json(out)


def load_multi_json(raw):
    raw = raw.strip()
    if not raw:
        return []
    dec = json.JSONDecoder()
    idx, out = 0, []
    while idx < len(raw):
        sub = raw[idx:].lstrip()
        if not sub:
            break
        obj, end = dec.raw_decode(sub)
        out.extend(obj if isinstance(obj, list) else [obj])
        idx += (len(raw[idx:]) - len(sub)) + end
    return out


def discover_projects(since, host):
    # `after` da API de events é EXCLUSIVO (não inclui o próprio dia) — subtrai 1 dia para não
    # perder projetos cujo único push do período caiu exatamente em `since`.
    day_before = (datetime.strptime(since, "%Y-%m-%d") - timedelta(days=1)).strftime("%Y-%m-%d")
    events = glab_api(f"events?action=pushed&after={day_before}&per_page=100", host=host, paginate=True)
    return sorted({e["project_id"] for e in events})


def project_info(pid, host):
    info = glab_api(f"projects/{pid}", host=host)[0]
    return info.get("path_with_namespace", str(pid)), info.get("default_branch")


def commit_branches(pid, sha, host):
    """Branches que contêm o commit; None se a API falhar (não silenciar como 'em nenhuma')."""
    try:
        refs = glab_api(f"projects/{pid}/repository/commits/{sha}/refs?type=branch&per_page=100",
                        host=host, paginate=True)
    except subprocess.CalledProcessError:
        return None
    return sorted(r["name"] for r in refs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", required=True, help="YYYY-MM-DD")
    ap.add_argument("--until", default=None, help="YYYY-MM-DD (default: sem limite superior)")
    ap.add_argument("--emails", required=True, help="e-mails de autor separados por vírgula")
    ap.add_argument("--projects", help="IDs separados por vírgula; se omitido, descobre via events")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--host", default=None)
    args = ap.parse_args()

    my_emails = {e.strip() for e in args.emails.split(",")}

    if args.projects:
        project_ids = [p.strip() for p in args.projects.split(",")]
    else:
        project_ids = discover_projects(args.since, args.host)

    since_iso = f"{args.since}T00:00:00Z"
    until_param = f"&until={args.until}T23:59:59Z" if args.until else ""

    out_dir = os.path.join(args.out_dir, "commits")
    os.makedirs(out_dir, exist_ok=True)

    index = {}
    empty_projects = []
    for pid in project_ids:
        name, default_branch = project_info(pid, args.host)
        commits = glab_api(
            f"projects/{pid}/repository/commits?since={since_iso}{until_param}&all=true&per_page=100",
            host=args.host, paginate=True,
        )
        mine = [c for c in commits if c.get("author_email") in my_emails]
        mine = [c for c in mine if not c["title"].lower().startswith("merge branch")]
        # dedupe por sha (all=true pode repetir o mesmo commit se ele existe em várias refs)
        seen = set()
        deduped = []
        for c in mine:
            if c["id"] in seen:
                continue
            seen.add(c["id"])
            branches = commit_branches(pid, c["id"], args.host)
            deduped.append({
                "id": c["short_id"],
                "date": c["created_at"],
                "title": c["title"],
                "message": c.get("message", "").strip(),
                "web_url": c.get("web_url"),
                "na_default_branch": None if branches is None else default_branch in branches,
                "branches": branches,
            })
        deduped.sort(key=lambda c: c["date"])

        if not deduped:
            empty_projects.append({"project_id": pid, "name": name})
            continue

        with open(os.path.join(out_dir, f"{pid}.json"), "w", encoding="utf-8") as f:
            json.dump({"project_id": pid, "name": name, "default_branch": default_branch, "commits": deduped},
                      f, ensure_ascii=False, indent=2)
        index[str(pid)] = {"name": name, "commit_count": len(deduped),
                           "fora_da_default_branch": sum(1 for c in deduped if c["na_default_branch"] is not True)}

    with open(os.path.join(out_dir, "_index.json"), "w", encoding="utf-8") as f:
        json.dump({"projects_com_commits": index, "projects_sem_commits_do_autor": empty_projects},
                   f, ensure_ascii=False, indent=2)

    total = sum(v["commit_count"] for v in index.values())
    fora = sum(v["fora_da_default_branch"] for v in index.values())
    print(f"Total: {total} commits em {len(index)} projeto(s) ({fora} fora da branch padrão ou sem refs). "
          f"{len(empty_projects)} projeto(s) tocado(s) no período sem commit desse autor "
          f"(ver _index.json — pode indicar e-mail de autor faltando em --emails).")


if __name__ == "__main__":
    main()
