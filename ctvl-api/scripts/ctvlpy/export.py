"""Export determinístico (YAML versionável) e listagens legíveis do estado atual do vault.

O export usa lista branca de campos: ids, hashes de senha, tokens, sessões e IPs nunca entram.
Ordenação estável e sem data/hora: dois exports do mesmo estado são idênticos byte a byte.
"""
import re

import yaml

from .client import CtvlError
from .state import REF_FIELDS, normalize

_FORBIDDEN = [
    (re.compile(r"eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\."), "JWT"),
    (re.compile(r"\$(?:2[aby]|argon2\w*|pbkdf2[\w-]*)\$|pbkdf2_sha\d+\$|argon2\$", re.I), "hash de senha"),
    (re.compile(r"(?i)\bbearer\s+\S{8,}"), "cabeçalho Authorization"),
    (re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"), "endereço IP"),
    (re.compile(r"(?im)^\s*-?\s*(password|senha|secret|token)\s*:\s*\S"), "campo de segredo"),
]


def assert_no_secrets(text):
    for rx, what in _FORBIDDEN:
        m = rx.search(text)
        if m:
            raise CtvlError("export abortado: possível %s no conteúdo (nada foi gravado)" % what)


def _split_perms(perms, subj):
    """(gerenciáveis, ignoradas). Ignoradas: sem chave ou com asymkey/opaqueobj; ordem estável."""
    managed, ignored = [], []
    for p in perms:
        if p.get("chave") is None or p.get("asymkey") or p.get("opaqueobj"):
            ignored.append(p)
        else:
            managed.append(p)
    ignored.sort(key=lambda p: (str(p[subj]), str(p.get("chave") or ""), str(p.get("asymkey") or ""),
                                str(p.get("opaqueobj") or ""), bool(p["tokenize"]), bool(p["detokenize"])))
    return managed, ignored


def build_export(state, refs, convencao, ambiente):
    N = normalize(state, refs, convencao)
    rec = {}
    rec["chaves"] = N["chaves"]
    rec["charsets"] = [{"nome": c["nome"], "alphabet": c["alphabet"], "range": c["range"]}
                       for c in N["charsets"] if not c["predefined"]]
    rec["charsets_predefinidos"] = sorted(c["nome"] for c in N["charsets"] if c["predefined"])
    rec["grupos"] = N["grupos"]
    rec["mascaras"] = N["mascaras"]
    rec["tokengroups"] = N["tokengroups"]
    rec["templates"] = N["templates"]
    rec["usuarios"] = N["usuarios"]
    # Só permissões sobre CHAVE são gerenciáveis. As sem chave ou sobre asymkey/opaqueobj vão para a
    # seção informativa (o loader a ignora com um aviso), senão o próprio export não voltaria no plan.
    rec["permissoes_usuarios"], ign_u = _split_perms(N["permissoes_usuarios"], "usuario")
    rec["permissoes_grupos"], ign_g = _split_perms(N["permissoes_grupos"], "grupo")
    if ign_u or ign_g:
        rec["ignorados"] = {k: v for k, v in (("permissoes_usuarios", ign_u), ("permissoes_grupos", ign_g)) if v}
    observadas = {}
    for f in sorted(REF_FIELDS):
        m, origem = refs.mode(f)
        if m:
            observadas[f] = "%s (%s)" % (m, origem)
    doc = {
        "versao": 1,
        "gerado_por": "ctvl-api export",
        "ambiente": ambiente,
        "convencao": {"sistemas": list(convencao["sistemas"]), "datatypes": list(convencao["datatypes"])},
        "api": {"refs_observadas": observadas},
        "recursos": rec,
    }
    return doc


def dump_yaml(doc):
    header = ("# Configuração do CT-VL exportada por ctvl-api. SEM senhas, tokens, hashes ou ids.\n"
              "# Determinística (ordem estável, sem data): serve para versionar e comparar com git diff.\n"
              "# Senhas de usuários novos vêm de password_ref (env:CTVL_<USUARIO>_PASSWORD) no import.\n")
    text = yaml.safe_dump(doc, sort_keys=False, allow_unicode=True, default_flow_style=False, width=120)
    out = header + text
    assert_no_secrets(out)
    return out


# ----------------------------------------------------------------------------- tabelas

def table(rows, cols):
    """cols: [(titulo, chave)]; devolve texto alinhado."""
    data = [[str(r.get(k, "")) if r.get(k) is not None else "-" for _, k in cols] for r in rows]
    head = [t for t, _ in cols]
    w = [max(len(head[i]), *(len(r[i]) for r in data)) if data else len(head[i]) for i in range(len(cols))]
    fmt = "  ".join("%%-%ds" % x for x in w)
    lines = [fmt % tuple(head), fmt % tuple("-" * x for x in w)]
    lines += [fmt % tuple(r) for r in data]
    return "\n".join(lines)


def _yn(v):
    return "sim" if v else "não"


def list_rows(resource, N):
    """(linhas, colunas) de uma listagem legível, ou (dados, None) para saída só estruturada."""
    if resource == "masks":
        return N["mascaras"], [("MÁSCARA", "nome"), ("ESQUERDA", "show_left"), ("DIREITA", "show_right"), ("CHAR", "mask_char")]
    if resource == "users":
        rows = []
        for u in N["usuarios"]:
            cn = u.get("convencao_nome")
            rows.append({"nome": u["nome"], "ativo": _yn(u["ativo"]), "mascara": u["mascara"] or "(sem máscara: vê completo)",
                         "grupos": ",".join(u["grupos"]) or "-",
                         "padrao": ("%s/%s/%s" % (cn["sistema"], cn["datatype"], cn["esquema"] or "-")) if cn
                         else "FORA DO PADRÃO: " + "; ".join(u.get("fora_do_padrao", []))})
        return rows, [("USUÁRIO", "nome"), ("ATIVO", "ativo"), ("MÁSCARA", "mascara"), ("GRUPOS", "grupos"),
                      ("SISTEMA/DATATYPE/ESQUEMA", "padrao")]
    if resource == "groups":
        return N["grupos"], [("GRUPO", "nome")]
    if resource == "tokengroups":
        return N["tokengroups"], [("TOKENGROUP", "nome"), ("CHAVE", "chave")]
    if resource == "templates":
        rows = [{**t, "irreversible": _yn(t["irreversible"]), "allow_small_input": _yn(t["allow_small_input"]),
                 "preserve_null_or_1_char": _yn(t["preserve_null_or_1_char"])} for t in N["templates"]]
        return rows, [("TEMPLATE", "nome"), ("TOKENGROUP", "tokengroup"), ("FORMAT", "format"), ("CHARSET", "charset"),
                      ("KL", "keep_left"), ("KR", "keep_right"), ("IRREV", "irreversible"),
                      ("PEQUENOS", "allow_small_input"), ("PREFIXO", "prefix")]
    if resource == "charsets":
        rows = [{"nome": c["nome"], "predefined": _yn(c["predefined"]), "range": _yn(c["range"]),
                 "alphabet": (c["alphabet"] or "")[:30]} for c in N["charsets"]]
        return rows, [("CHARSET", "nome"), ("PREDEFINIDO", "predefined"), ("FAIXA", "range"), ("ALFABETO", "alphabet")]
    if resource == "keys":
        return [{"nome": k["nome"], "seedkey": _yn(k.get("seedkey"))} for k in N["chaves"]], \
               [("CHAVE", "nome"), ("SEMENTE", "seedkey")]
    if resource == "formats":
        return [{"nome": n} for n in N["formats"]], [("FORMATO", "nome")]
    if resource == "permissions":
        rows = []
        for p in N["permissoes_usuarios"]:
            rows.append({"tipo": "usuario", "sujeito": p["usuario"], "chave": p["chave"],
                         "tokenize": _yn(p["tokenize"]), "detokenize": _yn(p["detokenize"])})
        for p in N["permissoes_grupos"]:
            rows.append({"tipo": "grupo", "sujeito": p["grupo"], "chave": p["chave"],
                         "tokenize": _yn(p["tokenize"]), "detokenize": _yn(p["detokenize"])})
        return rows, [("TIPO", "tipo"), ("SUJEITO", "sujeito"), ("CHAVE", "chave"), ("TOKENIZE", "tokenize"),
                      ("DETOKENIZE", "detokenize")]
    raise CtvlError("recurso desconhecido: %s" % resource)


RESOURCES = ["masks", "users", "groups", "tokengroups", "templates", "charsets", "keys", "formats", "permissions"]
