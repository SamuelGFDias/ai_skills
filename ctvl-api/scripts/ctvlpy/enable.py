"""enable-detokenize: o ÚNICO caminho que escreve canGet=true para um perfil mascarado.

O `apply` nunca sobe o detokenize de usuário mascarado (nem de grupo com membro mascarado). Aqui, por usuário
e com `--yes`, todas as pré-condições são verificadas e falham FECHADO antes de qualquer escrita:
  a) o usuário existe no vault e é perfil mascarado no arquivo, com permissão de detokenize declarada;
  b) a máscara atribuída a ele no vault é EXATAMENTE a declarada e a referência user.mask resolve;
  c) a máscara declarada existe no vault, com os mesmos parâmetros, e não está pendente/bloqueada;
  d) nenhum grupo do usuário concede detokenize (a soma grupo+usuário no CT-VL não foi confirmada);
  e) as senhas necessárias ao verify-mask (usuário e usuário de tokenize) estão no ambiente;
  f) referências de escrita confirmadas e chave não compartilhada sem opt-in.
Depois da escrita roda o verify-mask só para esse usuário (a API de dados só detokeniza com canGet=true, por
isso a conferência vem logo após o PUT) e REVERTE para canGet=false se divergir ou falhar.
"""
from . import verify as vf
from .client import CtvlError, HttpFailure
from .plan import _detail, build_plan
from .state import ID_FIELD, RAW_PATHS, RefUnconfirmed, load_state, normalize

SAMPLES = {"cpf": "52998224725", "cns": "898001160660001"}  # valores FABRICADOS


def _checks(D, state, refs, usuario, env, tokenize_user):
    """Devolve (problemas, contexto). Nunca escreve nem chama a rede."""
    probs, ctx = [], {}
    N = normalize(state, refs, D.convencao)
    users = {x["nome"]: x for x in N["usuarios"]}
    masks = {x["nome"]: x for x in N["mascaras"]}
    cur = users.get(usuario)
    if cur is None:
        return ["(a) usuário '%s' não existe no vault" % usuario], ctx
    decl = D.items["usuarios"].get(usuario)
    if not decl or not decl.get("mascara"):
        return ["(a) '%s' não é perfil mascarado no arquivo (sem 'mascara'): o apply já cuida do canGet dele" % usuario], ctx
    perms = [p for p in D.items["permissoes_usuarios"].values() if p["usuario"] == usuario and p["detokenize"]]
    if not perms:
        return ["(a) o arquivo não declara permissão de detokenize para '%s'" % usuario], ctx
    ctx.update(decl=decl, perms=perms)
    P = build_plan(D, state, refs, {"env": env})

    # (b)
    mname, resolved = refs.to_name("user.mask", state.by_name("usuarios")[usuario].get("mask"))
    if not cur["mascara"]:
        probs.append("(b) o usuário está sem máscara atribuída no vault (atribua '%s' na GUI do vault)" % decl["mascara"])
    elif not resolved:
        probs.append("(b) a referência user.mask não resolve (formato a confirmar): rode probe-refs e declare api.refs.user.mask")
    elif mname != decl["mascara"]:
        probs.append("(b) a máscara atribuída é '%s', diferente da declarada '%s'" % (mname, decl["mascara"]))
    # (c)
    md = D.items["mascaras"].get(decl["mascara"])
    mv = masks.get(decl["mascara"])
    if md is None:
        probs.append("(c) a máscara '%s' não está declarada no arquivo" % decl["mascara"])
    elif md.get("bloqueios"):
        probs.append("(c) a máscara '%s' está pendente de confirmação: %s" % (decl["mascara"], "; ".join(md["bloqueios"])))
    elif mv is None:
        probs.append("(c) a máscara '%s' não existe no vault" % decl["mascara"])
    else:
        diff = [k for k in ("show_left", "show_right", "mask_char") if mv.get(k) != md.get(k)]
        if diff:
            probs.append("(c) a máscara '%s' no vault difere da declarada em %s" % (decl["mascara"], ", ".join(diff)))
    # (d)
    groups = set(cur["grupos"]) | set(decl["grupos"])
    if groups and refs.mode("user.groups")[0] is None:
        probs.append("(d) não consigo ler os grupos do usuário (referência user.groups a confirmar)")
    for r in state.raw["permissoes_grupos"]:
        gname, ok = refs.to_name("perm_group.group", r.get("group"))
        if not ok:
            probs.append("(d) permissão de grupo com referência que não resolve (perm_group.group a confirmar)")
            break
        if gname in groups and r.get("canGet"):
            probs.append("(d) o grupo '%s' do usuário tem canGet=true: a soma de permissão grupo+usuário no CT-VL não "
                         "está confirmada; tire o usuário do grupo ou rebaixe o grupo" % gname)
    # (e)
    cn = decl.get("convencao_nome") or {}
    sistema, datatype = cn.get("sistema"), cn.get("datatype")
    tg = perms[0].get("tokengroup")
    tpl = None
    try:
        _, ts = vf.pick_users(D, sistema, datatype, tokenize_user)
        for v, quem in ((decl["password_ref"][4:], usuario), (D.items["usuarios"][ts]["password_ref"][4:], ts)):
            if not env.get(v):
                probs.append("(e) variável %s (senha de %s) não está definida: o verify-mask não pode rodar" % (v, quem))
        ctx["ts"] = ts
    except (CtvlError, KeyError) as e:
        probs.append("(e) verify-mask não é possível: %s" % e)
    cand = [t for t in D.items["templates"].values() if t["nome"].lower() == "%s_%s" % (sistema, datatype)]
    if len(cand) == 1:
        tg, tpl = tg or cand[0]["tokengroup"], cand[0]["nome"]
    if not tg or not tpl:
        probs.append("(e) não deduzi tokengroup/template do verify-mask para %s/%s" % (sistema, datatype))
    if datatype not in SAMPLES:
        probs.append("(e) sem valor de teste fabricado para o datatype '%s'" % datatype)
    ctx.update(sistema=sistema, datatype=datatype, tg=tg, tpl=tpl)
    # (f) o que o plano já bloqueia (referência, chave de outro tokengroup, chave compartilhada)
    for p in perms:
        act = next((a for a in P.actions if a.kind == "permissoes_usuarios" and a.nome == p["nome"]), None)
        if act is None or act.op in ("BLOQUEADO", "CONFLITO"):
            probs.append("(f) a permissão %s está %s no plano: %s" % (
                p["nome"], act.op if act else "ausente", "; ".join(act.motivo) if act else ""))
            continue
        chave = p.get("chave") or P.chave_of.get(p.get("tokengroup"))
        sp = P.share_problem(p.get("tokengroup"), chave)
        if sp:
            probs.append("(f) " + sp)
        for f in ("perm_user.user", "perm_user.key"):
            try:
                refs.write_mode(f)
            except RefUnconfirmed as e:
                probs.append("(f) " + str(e))
        ctx.setdefault("perm_chaves", {})[p["nome"]] = chave
    return probs, ctx


def _perm_row(state, refs, usuario, chave):
    for r in state.raw["permissoes_usuarios"]:
        if refs.to_name("perm_user.user", r.get("user"))[0] == usuario and \
                refs.to_name("perm_user.key", r.get("key"))[0] == chave:
            return r
    return None


def _put_or_post(D, client, refs, usuario, p, chave, row, can_get, out):
    body = {"user": refs.to_api("perm_user.user", usuario), "key": refs.to_api("perm_user.key", chave),
            "canPost": bool(p["tokenize"]), "canGet": can_get}
    if row is not None:
        method, path = "PUT", _detail(D, "permissoes_usuarios", row.get(ID_FIELD["permissoes_usuarios"]))
    else:
        method, path = "POST", RAW_PATHS["permissoes_usuarios"]
    out("EXECUTA  %s %s (perm.usuário %s)  canGet=%s" % (method, path, p["nome"], can_get))
    st, data = client.request(method, path, body=body)
    if not 200 <= st < 300:
        raise HttpFailure(st, method, path, data)
    out("  -> HTTP %s" % st)
    if row is None and isinstance(data, dict) and data.get(ID_FIELD["permissoes_usuarios"]) is not None:
        row = data
    return row


def run(D, state, client, refs, usuario, yes, out, env, sample=None, tokenize_user=None):
    """0 = habilitado/dry-run ok; 3 = pré-condição falhou; 4 = verify falhou (revertido)."""
    probs, ctx = _checks(D, state, refs, usuario, env, tokenize_user)
    out("enable-detokenize %s%s" % (usuario, "" if yes else "  (dry-run: nada será escrito)"))
    if probs:
        out("RECUSADO (nada foi escrito):")
        for m in probs:
            out("  - " + m)
        return 3
    out("pré-condições (a)-(f) ok: usuário existe e é mascarado; máscara '%s' atribuída = declarada e igual no vault; "
        "nenhum grupo com canGet=true; senhas do verify-mask presentes; referências confirmadas" % ctx["decl"]["mascara"])
    sample = sample or SAMPLES[ctx["datatype"]]
    todo = []
    for p in ctx["perms"]:
        chave = ctx["perm_chaves"][p["nome"]]
        row = _perm_row(state, refs, usuario, chave)
        todo.append((p, chave, row))
        ja = bool(row and row.get("canGet"))
        out("  %s: %s" % (p["nome"], "já está canGet=true (só conferir)" if ja else
                         ("PUT canGet=true (existe)" if row else "POST com canGet=true (não existe)")))
    if not yes:
        out("Depois da escrita: verify-mask só deste usuário (valor fabricado); se divergir ou falhar, reverte para "
            "canGet=false. Rode de novo com --yes para executar.")
        return 0
    written = []
    try:
        for p, chave, row in todo:
            if row is not None and row.get("canGet"):
                continue
            new_row = _put_or_post(D, client, refs, usuario, p, chave, row, True, out)
            written.append((p, chave, new_row))
    except (CtvlError, RefUnconfirmed, ValueError) as e:
        _rollback(D, client, refs, usuario, written, out)
        raise CtvlError("escrita interrompida (%s); o que foi escrito foi revertido para canGet=false" % e)
    bad, why = 0, ""
    try:
        bad = vf.run(D, ctx["sistema"], ctx["datatype"], sample, ctx["tg"], ctx["tpl"], tokenize_user, False, out,
                     only_user=usuario)
    except CtvlError as e:
        bad, why = 1, str(e)
    if bad:
        out("VERIFY FALHOU%s: revertendo canGet=false" % (" (%s)" % why if why else ""))
        _rollback(D, client, refs, usuario, written, out)
        return 4
    state2 = load_state(client)
    for p, chave, _ in todo:
        r2 = _perm_row(state2, refs, usuario, chave)
        if not (r2 and r2.get("canGet")):
            raise CtvlError("a releitura não mostra canGet=true em %s" % p["nome"])
    out("HABILITADO: %s com canGet=true; verify-mask ok; releitura confirmada." % usuario)
    return 0


def _rollback(D, client, refs, usuario, written, out):
    for p, chave, row in written:
        if row is None or row.get(ID_FIELD["permissoes_usuarios"]) is None:
            out("ERRO: não consegui reverter %s (sem id da permissão): REVERTA MANUALMENTE canGet para false" % p["nome"])
            continue
        try:
            _put_or_post(D, client, refs, usuario, p, chave, row, False, out)
        except Exception as e:  # noqa: BLE001 - qualquer falha no rollback precisa ser gritada
            out("ERRO: rollback de %s falhou (%s): REVERTA MANUALMENTE canGet para false" % (p["nome"], e))
