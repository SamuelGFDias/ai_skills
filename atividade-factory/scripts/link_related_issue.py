#!/usr/bin/env python3
"""Cria um link "relates_to" entre a issue core recém-criada e uma issue aberta existente
que já cobre parte do tema (evita duplicar sem perder a rastreabilidade da sobreposição).

Usa a REST API de issue links (estável desde antes do work items, funciona em CE sem licença).

Uso:
    python3 link_related_issue.py \
        --project ses-rj/desenvolvimento/biae/biae --iid 90 \
        --target-project ses-rj/desenvolvimento/biae/biae --target-iid 83 \
        [--host HOST]
"""
import argparse
import json
import subprocess


def rest_post(path, fields, host=None):
    cmd = ["glab", "api", path]
    for k, v in fields.items():
        cmd += ["--raw-field", f"{k}={v}"]
    if host:
        cmd += ["--hostname", host]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True)
    ap.add_argument("--iid", required=True)
    ap.add_argument("--target-project", required=True)
    ap.add_argument("--target-iid", required=True)
    ap.add_argument("--host", default=None)
    args = ap.parse_args()

    project_enc = args.project.replace("/", "%2F")
    result = rest_post(
        f"projects/{project_enc}/issues/{args.iid}/links",
        {"target_project_id": args.target_project, "target_issue_iid": args.target_iid, "link_type": "relates_to"},
        host=args.host,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
