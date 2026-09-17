#!/usr/bin/env python3
"""Define start_date/due_date de uma issue a partir do range real de datas dos commits.

Para comprovação de serviço, a data da issue tem que refletir quando o trabalho foi
efetivamente feito (data dos commits), não a data em que a issue foi criada no tracker.

GitLab 18.x não suporta `start_date` via REST/`glab issue update` (só `due_date`) — o único
método é GraphQL `workItemUpdate` com `startAndDueDateWidget` (ver
o provider do tracker, seção "Definir Datas"). Se a issue já estiver
fechada, o GraphQL bloqueia alteração de data; este script reabre, define as datas e fecha de
novo automaticamente.

Uso:
    python3 set_issue_dates.py --project grupo/projeto --iid 90 \
        --start-date 2026-09-01 --due-date 2026-09-17 [--host HOST]

Convenção da atividade-factory: --start-date = data do commit mais antigo do grupo,
--due-date = data do commit mais recente do grupo (mesmo dia em grupos de 1 commit).
"""
import argparse
import json
import subprocess
import sys


def rest(path, host=None):
    cmd = ["glab", "api", path]
    if host:
        cmd += ["--hostname", host]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def graphql(query, host=None):
    cmd = ["glab", "api", "graphql", "-f", f"query={query}"]
    if host:
        cmd += ["--hostname", host]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        print(proc.stdout, file=sys.stderr)
        print(proc.stderr, file=sys.stderr)
        raise SystemExit(f"GraphQL falhou (exit {proc.returncode})")
    data = json.loads(proc.stdout)
    if "errors" in data:
        raise SystemExit(f"GraphQL retornou erros: {data['errors']}")
    return data["data"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True)
    ap.add_argument("--iid", required=True)
    ap.add_argument("--start-date", required=True)
    ap.add_argument("--due-date", required=True)
    ap.add_argument("--host", default=None)
    args = ap.parse_args()

    project_enc = args.project.replace("/", "%2F")
    issue = rest(f"projects/{project_enc}/issues/{args.iid}", host=args.host)
    gid = f"gid://gitlab/WorkItem/{issue['id']}"
    was_closed = issue["state"] == "closed"

    if was_closed:
        q = '''
        mutation {
          workItemUpdate(input: {
            id: "%s",
            stateEvent: REOPEN,
            startAndDueDateWidget: { startDate: "%s", dueDate: "%s" }
          }) { errors }
        }
        ''' % (gid, args.start_date, args.due_date)
    else:
        q = '''
        mutation {
          workItemUpdate(input: {
            id: "%s",
            startAndDueDateWidget: { startDate: "%s", dueDate: "%s" }
          }) { errors }
        }
        ''' % (gid, args.start_date, args.due_date)
    graphql(q, host=args.host)

    if was_closed:
        close_q = '''
        mutation {
          workItemUpdate(input: { id: "%s", stateEvent: CLOSE }) { errors }
        }
        ''' % gid
        graphql(close_q, host=args.host)

    print(f"OK: {args.project}#{args.iid} start_date={args.start_date} due_date={args.due_date} "
          f"(estava {'fechada' if was_closed else 'aberta'}, reaplicado o mesmo estado)")


if __name__ == "__main__":
    main()
