#!/usr/bin/env python3
"""Cria Tasks filhas nativas (work item hierarchy) sob uma issue "core" já existente.

GitLab (mesmo Community Edition, sem licença) expõe o widget HIERARCHY em Issue e o tipo
de work item "Task" — dá pra criar hierarquia real (não é preciso Epic/Premium). REST não
cria work items filhos; só GraphQL faz isso (workItemCreate + hierarchyWidget.parentId).

A issue "core" continua sendo criada pelo fluxo normal da skill issue-factory
(`glab issue create`, com anti-duplicata, título padronizado, labels, assignee). Este
script só cuida das Tasks filhas, uma por commit/pequeno cluster de commits, para servir
de evidência auditável (comprovação de serviço) sem perder granularidade num agrupador.

Uso:
    python3 create_child_tasks.py \
        --project ses-rj/desenvolvimento/biae/biae \
        --parent-iid 83 \
        --tasks-file tasks.json \
        [--host HOST]

tasks.json: lista de {"title": "...", "description": "..."}
    Convenção sugerida de título de task: "<sha curto> <resumo curto do commit>"
    Convenção sugerida de descrição: link do commit (web_url) + data + trecho da mensagem.

Saída (stdout): JSON com a lista de tasks criadas (iid, web_url) — usar para conferir e
para registrar na issue core, se quiser (ex.: colar os links no corpo dela depois).
"""
import argparse
import json
import subprocess
import sys


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


def rest(path, host=None):
    cmd = ["glab", "api", path]
    if host:
        cmd += ["--hostname", host]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def get_parent_gid(project, parent_iid, host):
    project_enc = project.replace("/", "%2F")
    issue = rest(f"projects/{project_enc}/issues/{parent_iid}", host=host)
    return f"gid://gitlab/WorkItem/{issue['id']}"


def get_task_type_id(project, host):
    q = '''
    query {
      project(fullPath: "%s") {
        workItemTypes { nodes { id name } }
      }
    }
    ''' % project
    data = graphql(q, host=host)
    for t in data["project"]["workItemTypes"]["nodes"]:
        if t["name"] == "Task":
            return t["id"]
    raise SystemExit(f"Tipo de work item 'Task' não encontrado no projeto {project} "
                      f"(instância pode não ter Tasks habilitado)")


def create_task(project, task_type_id, parent_gid, title, description, host):
    escaped_title = title.replace('\\', '\\\\').replace('"', '\\"')
    escaped_desc = description.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
    q = '''
    mutation {
      workItemCreate(input: {
        namespacePath: "%s",
        workItemTypeId: "%s",
        title: "%s",
        hierarchyWidget: { parentId: "%s" },
        descriptionWidget: { description: "%s" }
      }) {
        workItem { id iid webUrl }
        errors
      }
    }
    ''' % (project, task_type_id, escaped_title, parent_gid, escaped_desc)
    data = graphql(q, host=host)
    result = data["workItemCreate"]
    if result["errors"]:
        raise SystemExit(f"Erro ao criar task '{title}': {result['errors']}")
    return result["workItem"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True, help="path completo, ex: ses-rj/desenvolvimento/biae/biae")
    ap.add_argument("--parent-iid", required=True)
    ap.add_argument("--tasks-file", required=True)
    ap.add_argument("--host", default=None)
    args = ap.parse_args()

    with open(args.tasks_file, encoding="utf-8") as f:
        tasks = json.load(f)

    parent_gid = get_parent_gid(args.project, args.parent_iid, args.host)
    task_type_id = get_task_type_id(args.project, args.host)

    created = []
    for t in tasks:
        wi = create_task(args.project, task_type_id, parent_gid, t["title"], t.get("description", ""), args.host)
        created.append(wi)
        print(f"  criada: {wi['webUrl']}", file=sys.stderr)

    print(json.dumps(created, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
