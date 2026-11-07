#!/usr/bin/env python3
"""Gera references/endpoints.md a partir de references/swagger.json.

Nada é inventado: método, path, descrição, parâmetros de path/query e campos
obrigatórios do corpo vêm do próprio swagger. Uso:
    python3 gen-endpoints.py [swagger.json] [saida.md]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SW = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "references", "swagger.json")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "references", "endpoints.md")
METHODS = ["get", "post", "put", "patch", "delete"]


def deref(sw, schema):
    if not isinstance(schema, dict):
        return {}
    ref = schema.get("$ref")
    if ref:
        return sw["definitions"].get(ref.split("/")[-1], {})
    return schema


def body_info(sw, op):
    for p in op.get("parameters", []):
        if p.get("in") == "body":
            sch = deref(sw, p.get("schema", {}))
            name = (p.get("schema", {}).get("$ref") or "").split("/")[-1]
            req = sch.get("required", [])
            props = sch.get("properties", {})
            ro = sorted(k for k, v in props.items() if v.get("readOnly"))
            return name, req, sorted(props), ro
    return None


def main():
    with open(SW, encoding="utf-8") as f:
        sw = json.load(f)
    by_tag = {}
    for path, item in sw["paths"].items():
        common = item.get("parameters", [])
        for m in METHODS:
            op = item.get(m)
            if not op:
                continue
            tag = (op.get("tags") or ["(sem tag)"])[0]
            by_tag.setdefault(tag, []).append((path, m, op, common))

    L = []
    L.append("# CT-VL admin API: resumo de endpoints")
    L.append("")
    L.append("Gerado por `scripts/gen-endpoints.py` a partir de `references/swagger.json` "
             "(Swagger %s, `basePath` `%s`, esquema %s). Não edite à mão: regenere." % (
                 sw.get("swagger"), sw.get("basePath"), ",".join(sw.get("schemes", []))))
    L.append("")
    L.append("Autenticação: `Authorization: Bearer <JWT>`; o JWT vem de `POST /api-token-auth/` com "
             "`{username,password}`. O host no swagger original foi substituído por `<host>`.")
    L.append("")
    L.append("Legenda: **obrig.** = campos `required` do corpo no swagger; **somente leitura** = "
             "`readOnly` (o servidor ignora ou rejeita na escrita). Listagens paginam com `limit`/`offset` "
             "e devolvem `{count,next,previous,results}`.")
    L.append("")
    for tag in sorted(by_tag):
        L.append("## %s" % tag)
        L.append("")
        L.append("| Método | Path | Finalidade | Parâmetros | Corpo (obrig. / somente leitura) |")
        L.append("|---|---|---|---|---|")
        for path, m, op, common in sorted(by_tag[tag], key=lambda x: (x[0], METHODS.index(x[1]))):
            desc = (op.get("description") or op.get("operationId") or "").strip().replace("\n", " ")
            params = []
            for p in list(common) + list(op.get("parameters", [])):
                if p.get("in") in ("path", "query"):
                    txt = "%s `%s`%s" % (p["in"], p["name"], " (obrig.)" if p.get("required") else "")
                    if txt not in params:
                        params.append(txt)
            b = body_info(sw, op)
            if b:
                name, req, props, ro = b
                body = "`%s`: obrig. %s" % (name, ", ".join("`%s`" % r for r in req) or "nenhum")
                if ro:
                    body += "; somente leitura %s" % ", ".join("`%s`" % r for r in ro)
            else:
                body = ""
            L.append("| %s | `%s` | %s | %s | %s |" % (
                m.upper(), path, desc.replace("|", "/"), "<br>".join(params), body))
        L.append("")

    L.append("## Esquemas (campos)")
    L.append("")
    for name in sorted(sw["definitions"]):
        d = sw["definitions"][name]
        req = set(d.get("required", []))
        L.append("### %s" % name)
        L.append("")
        for k, v in d.get("properties", {}).items():
            flags = []
            if k in req:
                flags.append("obrig.")
            if v.get("readOnly"):
                flags.append("somente leitura")
            if "maxLength" in v:
                flags.append("máx %s" % v["maxLength"])
            if "pattern" in v:
                flags.append("pattern `%s`" % v["pattern"])
            t = v.get("type", "")
            if t == "array":
                t = "array de %s" % v.get("items", {}).get("type", "?")
            desc = (v.get("description") or "").strip().replace("\n", " ")
            L.append("- `%s` (%s)%s%s" % (k, t, (" [%s]" % "; ".join(flags)) if flags else "",
                                          (": " + desc) if desc else ""))
        L.append("")
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(L).rstrip("\n") + "\n")
    print("gerado:", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
