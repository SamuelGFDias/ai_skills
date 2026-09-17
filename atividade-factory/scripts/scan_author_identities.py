#!/usr/bin/env python3
"""Descobre quais author_email um mesmo usuário GitLab usou em commits recentes.

Uma pessoa pode assinar commits com e-mails diferentes (conta corporativa, pessoal,
de outra empresa contratada) dependendo da config local do git em cada clone. Filtrar
por um único e-mail (ex.: o da conta GitLab autenticada) sub-representa a atividade real.

Uso:
    python3 scan_author_identities.py --since 2026-09-01 [--projects 5,57,272] [--host gitlab-prod.saude.rj.gov.br]

Sem --projects, descobre projetos tocados no período via GET /events?action=pushed
do usuário autenticado (glab auth status).

Saída (stdout): JSON {"author_name_esperado": "...", "identities": [{"email":..., "name":..., "commit_count":...}]}
Não decide sozinho quais e-mails são "do usuário" — isso é uma confirmação humana
obrigatória antes de rodar collect_commits.py com --emails.
"""
import argparse
import json
import subprocess
import sys
from collections import Counter


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
    events = glab_api(f"events?action=pushed&after={since}&per_page=100", host=host, paginate=True)
    return sorted({e["project_id"] for e in events})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", required=True, help="YYYY-MM-DD")
    ap.add_argument("--projects", help="IDs separados por vírgula; se omitido, descobre via events")
    ap.add_argument("--host", default=None)
    args = ap.parse_args()

    me = glab_api("user", host=args.host)[0]
    expected_name = me["name"]

    if args.projects:
        project_ids = [p.strip() for p in args.projects.split(",")]
    else:
        project_ids = discover_projects(args.since, args.host)

    since_iso = f"{args.since}T00:00:00Z"
    counter = Counter()
    for pid in project_ids:
        commits = glab_api(
            f"projects/{pid}/repository/commits?since={since_iso}&all=true&per_page=100",
            host=args.host, paginate=True,
        )
        for c in commits:
            if c.get("author_name") == expected_name:
                counter[(c.get("author_email"), c.get("author_name"))] += 1

    identities = [
        {"email": email, "name": name, "commit_count": count}
        for (email, name), count in counter.most_common()
    ]
    print(json.dumps({"author_name_esperado": expected_name, "identities": identities}, ensure_ascii=False, indent=2))

    if not identities:
        print("Nenhum commit com author_name == nome da conta encontrado no período/projetos dados.", file=sys.stderr)


if __name__ == "__main__":
    main()
