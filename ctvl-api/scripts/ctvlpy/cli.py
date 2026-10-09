"""CLI do motor Python (chamada pelos scripts bash; não é pensada para uso direto)."""
import argparse
import json
import os
import re
import sys

import yaml

from . import export as ex
from . import plan as pl
from . import verify as vf
from .client import (AuthExpired, Client, CtvlError, EmptyClient, FixtureClient, HttpFailure,
                     client_from_env, jwt_ttl, login)
from .config import ConfigError, Desired, load_config, load_docs
from .mask import body_has_secret_key, mask_obj, mask_text
from .naming import DEFAULT_DATATYPES, DEFAULT_SISTEMAS, parse_mask_name, parse_user_name
from .state import REF_FIELDS, Refs, empty_state, load_state, normalize

WRITE = {"POST", "PUT", "PATCH", "DELETE"}
PATH_OK = re.compile(r"^/[^\s\x00-\x1f]*$")


def out(text=""):
    print(mask_text(str(text)))


def err(text):
    sys.stderr.write(mask_text(str(text)) + "\n")


def _json_out(obj):
    print(json.dumps(mask_obj(obj), ensure_ascii=False, indent=2))


# ----------------------------------------------------------------------------- utilidades

def load_desired(args, need=False):
    """Carrega --file e/ou --docs-dir. Sem nenhum e need=False devolve um Desired vazio."""
    key_map = {}
    for kv in getattr(args, "key_map", None) or []:
        if "=" not in kv:
            raise ConfigError("--key-map espera GRUPO=CHAVE (veio %r)" % kv)
        g, k = kv.split("=", 1)
        key_map[g] = k
    acc = getattr(args, "accept_suggestions", False)
    if getattr(args, "file", None):
        D = load_config(args.file, accept_suggestions=acc)
    elif need and not getattr(args, "docs_dir", None):
        raise ConfigError("informe --file ARQUIVO.yaml ou --docs-dir docs/tokenizacao-ctvl")
    else:
        D = Desired()
        D.accept_suggestions = acc
    if getattr(args, "docs_dir", None):
        load_docs(args.docs_dir, D, key_map=key_map, email_domain=getattr(args, "email_domain", None),
                  include_legacy=getattr(args, "include_legacy", False), accept_suggestions=acc)
    return D


def get_client_state(args, allow_offline=True):
    if getattr(args, "state_dir", None):
        c = FixtureClient(args.state_dir)
        return c, load_state(c)
    if getattr(args, "empty_state", False):
        return EmptyClient(), empty_state()
    c = client_from_env()
    return c, load_state(c)


def is_offline(args):
    return bool(getattr(args, "state_dir", None) or getattr(args, "empty_state", False))


# ----------------------------------------------------------------------------- subcomandos

def cmd_jwt_ttl(args):
    print(jwt_ttl(args.file))
    return 0


def cmd_login(args):
    user, pw = os.environ.get("CTVL_LOGIN_USER"), os.environ.get("CTVL_LOGIN_PASSWORD")
    if not user or not pw:
        raise CtvlError("login chamado sem credenciais (use ctvl-token.sh)")
    c = client_from_env()
    c.token_file = None
    login(c, user, pw, args.out)
    out("token obtido e guardado em cache (modo 600); valor não exibido; expira em ~%d s" % max(jwt_ttl(args.out), 0))
    return 0


def cmd_request(args):
    method = args.method.upper()
    path = args.path
    if method not in ("GET", "POST", "PUT", "PATCH", "DELETE"):
        raise CtvlError("método inválido: %s" % method)
    if not PATH_OK.match(path) or ".." in path.split("?")[0].split("/") or "//" in path.split("?")[0]:
        raise CtvlError("path inválido (precisa começar com / e ser relativo à base da API): %r" % path)
    if path.split("?")[0].rstrip("/") == "/api-token-auth":
        raise CtvlError("login não passa por aqui: use `ctvl.sh token <ambiente>` (a senha nunca vai em argumento)")
    body = None
    srcs = [bool(args.body), bool(args.body_file), args.body_stdin]
    if sum(srcs) > 1:
        raise CtvlError("use só um entre --body, --body-file, --body-stdin")
    try:
        if args.body:
            body = json.loads(args.body)
            if body_has_secret_key(body):
                raise CtvlError("o corpo tem campo de senha/segredo: não use --body (aparece em ps/histórico); "
                                "use --body-file (modo 600) ou --body-stdin")
        elif args.body_file:
            with open(args.body_file, encoding="utf-8") as f:
                body = json.load(f)
        elif args.body_stdin:
            body = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        raise CtvlError("corpo não é JSON válido: %s" % e)
    query = {}
    for kv in args.query or []:
        if "=" not in kv:
            raise CtvlError("--query espera chave=valor")
        k, v = kv.split("=", 1)
        query[k] = v
    c = client_from_env()
    shown = "%s %s%s" % (method, c.base, path)
    err("[ctvl] vai executar: %s%s" % (shown, ("  corpo=" + json.dumps(mask_obj(body), ensure_ascii=False)) if body is not None else ""))
    if method in WRITE and not args.yes:
        err("[ctvl] NADA foi enviado: operação de escrita exige --yes explícito.")
        return 2
    if method == "GET" and args.all:
        data = c.get_all(path, query=query or None)
        _json_out(data)
        return 0
    st, data = c.request(method, path, body=body, query=query or None)
    if not 200 <= st < 300:
        raise HttpFailure(st, method, path, data)
    err("[ctvl] HTTP %s" % st)
    if isinstance(data, (dict, list)):
        _json_out(data)
    elif data:
        out(str(data)[:2000])
    return 0


def _convencao(D):
    return D.convencao


def cmd_list(args):
    D = load_desired(args)
    c, state = get_client_state(args)
    refs = Refs(state, D.api["refs"])
    N = normalize(state, refs, D.convencao)
    res = args.resource
    targets = ex.RESOURCES if res == "all" else [res]
    if args.format == "yaml":
        doc = {}
        for r in targets:
            rows, _ = ex.list_rows(r, N)
            doc[r] = rows
        print(mask_text(yaml.safe_dump(doc, sort_keys=False, allow_unicode=True, default_flow_style=False)), end="")
        return 0
    if args.format == "json":
        _json_out({r: ex.list_rows(r, N)[0] for r in targets})
        return 0
    for r in targets:
        rows, cols = ex.list_rows(r, N)
        out("== %s (%d)" % (r, len(rows)))
        out(ex.table(rows, cols))
        out("")
    fora = [u["nome"] for u in N["usuarios"] if "fora_do_padrao" in u]
    if fora and res in ("users", "all"):
        out("AVISO: %d usuário(s) fora da convenção <sistema>_<datatype>[_<esquema>]: %s" % (len(fora), ", ".join(fora)))
    return 0


def cmd_export(args):
    D = load_desired(args)
    c, state = get_client_state(args)
    refs = Refs(state, D.api["refs"])
    doc = ex.build_export(state, refs, D.convencao, os.environ.get("CTVL_ALIAS", args.ambiente or "offline"))
    text = ex.dump_yaml(doc)
    fora = [u["nome"] for u in doc["recursos"]["usuarios"] if "fora_do_padrao" in u]
    if args.out:
        tmp = args.out + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, args.out)
        err("[ctvl] exportado para %s (%d usuários, %d templates, %d máscaras)" % (
            args.out, len(doc["recursos"]["usuarios"]), len(doc["recursos"]["templates"]), len(doc["recursos"]["mascaras"])))
    else:
        print(text, end="")
    if fora:
        err("[ctvl] AVISO: %d usuário(s) fora da convenção: %s" % (len(fora), ", ".join(fora)))
    return 0


def is_verbose(args):
    """--verbose ou CTVL_VERBOSE=1 (qualquer valor que não seja vazio/0/false/no/off): texto completo de cada item."""
    if getattr(args, "verbose", False):
        return True
    return os.environ.get("CTVL_VERBOSE", "").strip().lower() not in ("", "0", "false", "no", "off")


def _print_manuais(P, verbose=True):
    if not P.manuais:
        return
    if verbose:
        out("Pendências manuais (a skill não executa; não esqueça):")
        for m in P.manuais:
            out("  - " + m)
        return
    rotina, outras = pl.manuais_split(P)
    partes = (["%d enable-detokenize" % len(rotina)] if rotina else []) + (["%d aviso(s)/divergência(s)" % len(outras)] if outras else [])
    out("Pendências manuais (a skill não executa; detalhes no plano acima): " + ", ".join(partes))


def _sync_common(args, apply):
    D = load_desired(args, need=True)
    for w in D.warnings:
        err("AVISO: " + w)
    c, state = get_client_state(args)
    refs = Refs(state, D.api["refs"])
    opts = {"allow_breaking_update": args.allow_breaking_update}
    P = pl.finalize(pl.build_plan(D, state, refs, opts))
    verbose = is_verbose(args)
    if verbose:
        out(pl.render(P, show_extra=args.show_extra))
    else:
        out(pl.render_compact(P, D, os.environ.get("CTVL_ALIAS") or "offline", show_extra=args.show_extra))
    counts = P.count()
    blocked = [a for a in P.actions if a.op in ("BLOQUEADO", "CONFLITO")]
    if not apply:
        if args.check and (blocked or P.pending_writes() or P.manuais):
            return 1
        if blocked and not args.check:
            err("[ctvl] AVISO: %d item(ns) BLOQUEADO/CONFLITO neste plano; o plan sai com 0 mesmo assim: use --check "
                "em CI para falhar." % len(blocked))
        return 0
    if is_offline(args):
        raise CtvlError("apply precisa do vault real (não use --state-dir/--empty-state)")
    if not args.yes:
        err("[ctvl] NADA foi aplicado: apply exige --yes explícito (acima está o plano).")
        return 2
    if blocked and not args.skip_blocked:
        err("[ctvl] %d item(ns) BLOQUEADO/CONFLITO: nada foi aplicado. Resolva, ou use --skip-blocked para aplicar "
            "o restante (os dependentes dos bloqueados são pulados junto: template, usuário só de permissão e "
            "permissão de um tokengroup bloqueado)." % len(blocked))
        pend = [a for a in P.pending_writes() if a.rebaixa]
        if pend:  # as pendências manuais (com o AVISO de cada permissão) já saíram no plano impresso acima
            err("[ctvl] ATENÇÃO: %d linha(s) de permissão mascarada(s) mantêm canGet=true no vault; use --skip-blocked "
                "para aplicar os rebaixamentos (e o resto não bloqueado do plano)." % len(pend))
        if P.rebaixo_na:
            err("[ctvl] ATENÇÃO: %d permissão(ões) mascarada(s) mantêm canGet=true no vault e o rebaixamento NÃO é "
                "aplicável pela skill (ver AVISO nas pendências manuais)." % P.rebaixo_na)
        return 3
    probs = pl.preflight(P, refs)
    if probs:
        err("[ctvl] apply abortado ANTES de escrever:")
        for p in probs:
            err("  - " + p)
        return 3
    if not P.pending_writes():
        out("Nada a aplicar: o vault já está de acordo com o arquivo.")
        _print_manuais(P, verbose)
        return 0
    n = pl.apply_plan(P, D, c, state, refs, out, compact=not verbose)
    out("Aplicado: %d operação(ões)." % n)
    _print_manuais(P, verbose)
    if not args.no_verify:
        left = pl.verify_after(D, c, opts)
        out("Verificação (replanejamento): %d ação(ões) ainda pendente(s) (esperado 0)." % len(left))
        if left:
            for a in left:
                out("  pendente: %s %s %s" % (a.op, pl.LABEL[a.kind], a.nome))
            return 4
    return 0


def cmd_plan(args):
    return _sync_common(args, apply=False)


def cmd_apply(args):
    return _sync_common(args, apply=True)


def cmd_enable_detokenize(args):
    from . import enable as en
    D = load_desired(args, need=True)
    for w in D.warnings:
        err("AVISO: " + w)
    c, state = get_client_state(args)
    refs = Refs(state, D.api["refs"])
    return en.run(D, state, c, refs, args.usuario, args.yes, out, os.environ, sample=args.sample,
                  tokenize_user=args.tokenize_user)


def cmd_probe_refs(args):
    D = load_desired(args)
    c, state = get_client_state(args)
    refs = Refs(state, D.api["refs"])
    rows = []
    for f in sorted(REF_FIELDS):
        owner, target, raw = REF_FIELDS[f]
        m, n = refs.evidence(f)
        conf = D.api["refs"].get(f)
        rows.append({"campo": f, "confirmado": conf or ("swagger: name" if f == "perm_user.user" else "-"),
                     "evidencia": m or "inconclusivo", "amostras": n,
                     "alvo": target})
    out(ex.table(rows, [("CAMPO", "campo"), ("CONFIRMADO", "confirmado"), ("EVIDÊNCIA NA LEITURA", "evidencia"),
                        ("AMOSTRAS", "amostras"), ("ALVO", "alvo")]))
    sug = {r["campo"]: r["evidencia"] for r in rows if r["evidencia"] in ("name", "id") and r["confirmado"] == "-"}
    out("")
    out("Evidência vem só de objetos que JÁ existem (leitura). Para escrever, confirme e declare no arquivo:")
    if sug:
        out("api:\n  refs:")
        for k, v in sug.items():
            out("    %s: %s" % (k, v))
    else:
        out("(sem evidência suficiente: crie/inspecione um exemplo na GUI ou use `ctvl.sh admin ... GET` num item e decida)")
    return 0


def cmd_names(args):
    D = load_desired(args)
    s, d = D.convencao["sistemas"], D.convencao["datatypes"]
    rows = []
    for n in args.names:
        r = parse_mask_name(n, s, d) if args.kind == "mask" else parse_user_name(n, s, d)
        rows.append({"nome": n, "sistema": r["sistema"], "datatype": r["datatype"], "esquema": r["esquema"],
                     "situacao": "OK" if r["conforme"] else "FORA DO PADRÃO: " + "; ".join(r["problemas"])})
    out(ex.table(rows, [("NOME", "nome"), ("SISTEMA", "sistema"), ("DATATYPE", "datatype"), ("ESQUEMA", "esquema"),
                        ("SITUAÇÃO", "situacao")]))
    return 0 if all(r["situacao"] == "OK" for r in rows) else 1


def cmd_check_config(args):
    D = load_desired(args, need=True)
    for w in D.warnings:
        out("AVISO: " + w)
    for k in ("chaves", "charsets", "grupos", "tokengroups", "templates", "mascaras", "usuarios",
              "permissoes_usuarios", "permissoes_grupos"):
        out("%-22s %d  %s" % (k, len(D.items[k]), ", ".join(D.names(k))[:160]))
    bl = [(k, n, b) for k in D.items for n, it in sorted(D.items[k].items()) for b in (it.get("bloqueios") or [])]
    for k, n, b in bl:
        out("BLOQUEIO  %s %s: %s" % (k, n, b))
    out("configuração válida (%d bloqueio(s) de conteúdo pendente)" % len(bl))
    return 0


def cmd_verify_mask(args):
    D = load_desired(args, need=True)
    tg = args.tokengroup
    tpl = args.template
    if not tg or not tpl:
        cand = [t for t in D.items["templates"].values()
                if t["nome"].lower() == "%s_%s" % (args.sistema, args.datatype)]
        if len(cand) == 1:
            tg, tpl = tg or cand[0]["tokengroup"], tpl or cand[0]["nome"]
    if not tg or not tpl:
        raise CtvlError("não deduzi tokengroup/template: informe --tokengroup e --template")
    bad = vf.run(D, args.sistema, args.datatype, args.sample, tg, tpl, args.tokenize_user, args.show_values, out)
    return 1 if bad else 0


# ----------------------------------------------------------------------------- parser

def build_parser():
    ap = argparse.ArgumentParser(prog="ctvl_core.py")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add(name, fn):
        sp = sub.add_parser(name)
        sp.set_defaults(fn=fn)
        return sp

    def conf_opts(sp, offline=True):
        sp.add_argument("--file")
        sp.add_argument("--docs-dir")
        sp.add_argument("--key-map", action="append", help="GRUPO=CHAVE (modo --docs-dir)")
        sp.add_argument("--email-domain")
        sp.add_argument("--include-legacy", action="store_true")
        sp.add_argument("--accept-suggestions", action="store_true")
        if offline:
            sp.add_argument("--state-dir")
            sp.add_argument("--empty-state", action="store_true")

    p = add("jwt-ttl", cmd_jwt_ttl)
    p.add_argument("file")
    p = add("login", cmd_login)
    p.add_argument("--out", required=True)

    p = add("request", cmd_request)
    p.add_argument("method")
    p.add_argument("path")
    p.add_argument("--body")
    p.add_argument("--body-file")
    p.add_argument("--body-stdin", action="store_true")
    p.add_argument("--query", action="append")
    p.add_argument("--all", action="store_true")
    p.add_argument("--yes", action="store_true")

    p = add("list", cmd_list)
    p.add_argument("resource", choices=ex.RESOURCES + ["all"])
    p.add_argument("--format", choices=["table", "yaml", "json"], default="table")
    conf_opts(p)

    p = add("export", cmd_export)
    p.add_argument("--out")
    p.add_argument("--ambiente")
    conf_opts(p)

    for name, fn in (("plan", cmd_plan), ("apply", cmd_apply)):
        p = add(name, fn)
        conf_opts(p)
        p.add_argument("--allow-breaking-update", action="store_true")
        p.add_argument("--skip-blocked", action="store_true")
        p.add_argument("--show-extra", action="store_true")
        p.add_argument("--check", action="store_true")
        p.add_argument("--yes", action="store_true")
        p.add_argument("--no-verify", action="store_true")
        p.add_argument("--verbose", action="store_true",
                       help="texto completo de cada item (padrão: saída compacta); também CTVL_VERBOSE=1")

    p = add("enable-detokenize", cmd_enable_detokenize)
    p.add_argument("usuario")
    conf_opts(p, offline=False)
    p.add_argument("--yes", action="store_true")
    p.add_argument("--sample", help="valor FABRICADO de teste (padrão: um valor sintético por datatype)")
    p.add_argument("--tokenize-user")

    p = add("probe-refs", cmd_probe_refs)
    conf_opts(p)

    p = add("names", cmd_names)
    p.add_argument("names", nargs="+")
    p.add_argument("--kind", choices=["user", "mask"], default="user")
    p.add_argument("--file")
    p.add_argument("--docs-dir")

    p = add("check-config", cmd_check_config)
    conf_opts(p, offline=False)

    p = add("verify-mask", cmd_verify_mask)
    conf_opts(p, offline=False)
    p.add_argument("--sistema", required=True)
    p.add_argument("--datatype", required=True)
    p.add_argument("--sample", required=True, help="valor FABRICADO de teste (nunca dado real)")
    p.add_argument("--tokengroup")
    p.add_argument("--template")
    p.add_argument("--tokenize-user")
    p.add_argument("--show-values", action="store_true")
    return ap


def main(argv):
    args = build_parser().parse_args(argv)
    try:
        return args.fn(args)
    except AuthExpired as e:
        err("[ctvl] " + str(e))
        return 77
    except (CtvlError, ConfigError) as e:
        err("ERRO: " + str(e))
        if isinstance(e, HttpFailure) and e.status == 403:
            err("Dica: 403 = o usuário autenticado não tem permissão de administração do vault. "
                "Não use credencial de dados (tokenize/detokenize) na API admin; peça a credencial admin ao responsável.")
        if isinstance(e, HttpFailure) and e.status == 405:
            err("Dica: 405 = método não permitido neste path (o nginx devolve 405 para != POST na API de dados).")
        return 1
    except BrokenPipeError:
        return 0
