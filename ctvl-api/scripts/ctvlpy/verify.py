"""Verificação da máscara pela API de DADOS (Basic): tokeniza com o usuário de serviço e detokeniza
com cada usuário do sistema/datatype, comparando com o esperado. Senhas só por variável de ambiente."""
import os
import time

from .client import Client, CtvlError
from .mask import mask_text
from .naming import password_var_problem


def expected(sample, mask):
    if not mask:
        return sample
    n, left, right = len(sample), mask["show_left"], mask["show_right"]
    if left + right >= n:
        return sample
    return sample[:left] + mask["mask_char"] * (n - left - right) + (sample[n - right:] if right else "")


def clear_positions(value, sample):
    return [i for i, ch in enumerate(value) if i < len(sample) and ch == sample[i]]


def _call(client, op, body, retries=2):
    last = None
    for attempt in range(retries + 1):
        st, data = client.request("POST", "/" + op, body=body)
        item = data[0] if isinstance(data, list) and data else data
        if isinstance(item, dict) and item.get("status") == "Succeed":
            return item
        reason = item.get("reason") if isinstance(item, dict) else str(item)[:200]
        last = "HTTP %s, status=%s, reason=%s" % (st, item.get("status") if isinstance(item, dict) else "?", mask_text(str(reason)))
        if "key name" in str(reason) and attempt < retries:
            time.sleep(1)  # falha intermitente medida em DEV: retry limitado
            continue
        break
    raise CtvlError("%s falhou (erro de negócio volta com HTTP 200): %s" % (op, last))


def pick_users(D, sistema, datatype, tokenize_user=None):
    """([(usuário, permissão)] do sistema/datatype, usuário de tokenize)."""
    users = []
    for nome in sorted(D.items["usuarios"]):
        u = D.items["usuarios"][nome]
        cn = u.get("convencao_nome") or {}
        if cn.get("sistema") != sistema or cn.get("datatype") not in (datatype, "svc"):
            continue
        perm = next((p for p in D.items["permissoes_usuarios"].values() if p["usuario"] == nome), None)
        users.append((u, perm))
    if not users:
        raise CtvlError("nenhum usuário de %s/%s no arquivo" % (sistema, datatype))
    ts = tokenize_user or next((u["nome"] for u, p in users if p and p["tokenize"]), None)
    if not ts:
        raise CtvlError("nenhum usuário com permissão tokenize para %s/%s; informe --tokenize-user" % (sistema, datatype))
    return users, ts


def run(D, sistema, datatype, sample, tokengroup, template, tokenize_user, show_values, out, only_user=None):
    """only_user: confere só esse usuário e trata senha ausente como falha (usado pelo enable-detokenize)."""
    users, ts = pick_users(D, sistema, datatype, tokenize_user)
    env = os.environ
    host, base = env.get("CTVL_CONN_HOST"), env.get("CTVL_CONN_DATA_BASE", "/vts/rest/v2.0")
    if not host:
        raise CtvlError("conexão não configurada: use ctvl.sh verify-mask <ambiente> ...")

    def client_for(nome):
        var = D.items["usuarios"][nome]["password_ref"][4:]
        problem = password_var_problem(var)
        if problem:
            raise CtvlError("usuário %s: %s" % (nome, problem))
        pw = env.get(var)
        if not pw:
            return None, var
        return Client(env.get("CTVL_CONN_SCHEME", "https"), host, base, ca=env.get("CTVL_CONN_CA") or None,
                      insecure=env.get("CTVL_CONN_INSECURE") == "1", basic=(nome, pw)), var

    c, var = client_for(ts)
    if c is None:
        raise CtvlError("defina a variável %s (senha do usuário de tokenize %s) no ambiente do processo" % (var, ts))
    tok = _call(c, "tokenize", {"tokengroup": tokengroup, "tokentemplate": template, "data": sample}).get("token")
    out("tokenize (%s): ok, token com %d caracteres (valor não exibido)" % (ts, len(tok or "")))
    rows, bad = [], 0
    for u, perm in users:
        if not (perm and perm["detokenize"]):
            continue
        if only_user and u["nome"] != only_user:
            continue
        c, var = client_for(u["nome"])
        if c is None and only_user:
            raise CtvlError("defina a variável %s (senha do usuário %s)" % (var, u["nome"]))
        if c is None:
            rows.append((u["nome"], u["mascara"] or "-", "PULADO", "defina %s" % var))
            continue
        mask = D.items["mascaras"].get(u["mascara"]) if u["mascara"] else None
        want = expected(sample, mask)
        got = _call(c, "detokenize", {"tokengroup": tokengroup, "tokentemplate": template, "token": tok}).get("data")
        ok = got == want
        bad += 0 if ok else 1
        det = "esperado %d chars, obtido %d; posições em claro: %s" % (
            len(want), len(got or ""), clear_positions(got or "", sample) or "nenhuma")
        if show_values:
            det += "; obtido=%r esperado=%r" % (got, want)
        rows.append((u["nome"], u["mascara"] or "(sem máscara)", "OK" if ok else "DIVERGE", det))
    out("%-30s %-28s %-8s %s" % ("USUÁRIO", "MÁSCARA", "RESULTADO", "DETALHE"))
    for r in rows:
        out("%-30s %-28s %-8s %s" % r)
    return bad
