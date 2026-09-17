#!/usr/bin/env python3
"""Coleta issues abertas do usuário (atribuídas + criadas), deduplicadas, por projeto.

Uso:
    python3 collect_open_issues.py --out-dir /caminho/workspace [--host HOST]

Saída: <out-dir>/issues/<project_id>.json por projeto com issues abertas (iid, title, web_url,
labels), só para os projetos que têm pelo menos uma. Projetos sem issue aberta do usuário
simplesmente não geram arquivo — a etapa de análise trata "sem arquivo" como "sem issue".
"""
import argparse
import json
import os
import subprocess


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--host", default=None)
    ap.add_argument("--scopes", default="assigned_to_me,created_by_me",
                     help="escopos do endpoint /issues a combinar (vírgula)")
    args = ap.parse_args()

    by_key = {}
    for scope in args.scopes.split(","):
        issues = glab_api(f"issues?scope={scope}&state=opened&per_page=100", host=args.host, paginate=True)
        for i in issues:
            key = (i["project_id"], i["iid"])
            by_key[key] = {
                "iid": i["iid"],
                "title": i["title"],
                "web_url": i["web_url"],
                "labels": i.get("labels", []),
            }

    by_project = {}
    for (pid, iid), v in by_key.items():
        by_project.setdefault(str(pid), []).append(v)

    out_dir = os.path.join(args.out_dir, "issues")
    os.makedirs(out_dir, exist_ok=True)
    for pid, issues in by_project.items():
        with open(os.path.join(out_dir, f"{pid}.json"), "w", encoding="utf-8") as f:
            json.dump(issues, f, ensure_ascii=False, indent=2)

    print(f"Total: {len(by_key)} issue(s) aberta(s) única(s) em {len(by_project)} projeto(s).")


if __name__ == "__main__":
    main()
