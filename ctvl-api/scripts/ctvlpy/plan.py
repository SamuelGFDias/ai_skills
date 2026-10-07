"""plan/apply declarativo e idempotente.

Ordem de dependência: chaves -> charsets -> grupos -> tokengroups -> templates -> máscaras ->
usuários -> permissões de token. Nunca deleta. O que não está confirmado não é adivinhado:
vira BLOQUEADO (plan) ou falha antes de qualquer escrita (apply).
"""
import os

from .client import CtvlError, HttpFailure
from .mask import mask_obj, mask_text
from .naming import password_var_problem
from .state import (DETAIL_PATH, ID_FIELD, RAW_PATHS, RefUnconfirmed, Refs, load_state, normalize)

ORDER = ["chaves", "charsets", "grupos", "tokengroups", "templates", "mascaras", "usuarios",
         "permissoes_usuarios", "permissoes_grupos"]
LABEL = {"chaves": "chave", "charsets": "charset", "grupos": "grupo", "tokengroups": "tokengroup",
         "templates": "template", "mascaras": "máscara", "usuarios": "usuário",
         "permissoes_usuarios": "perm.usuário", "permissoes_grupos": "perm.grupo"}
TEMPLATE_COMPARE = ["tokengroup", "format", "charset", "keep_left", "keep_right", "irreversible",
                    "allow_small_input", "preserve_null_or_1_char", "prefix", "start_year", "end_year",
                    "date_record_count", "date_table_num"]
TEMPLATE_REF = {"tokengroup": "template.tenant", "format": "template.format", "charset": "template.charset"}


class Action:
    def __init__(self, kind, nome, op, motivo=None):
        self.kind, self.nome, self.op = kind, nome, op
        self.motivo = list(motivo or [])
        self.diffs = []
        self.refs_needed = []
        self.env_needed = []
        self.build = None
        self.method = None
        self.path = None
        self.deps = []
        self.needed_by = []  # usuário criado só para estas permissões: se todas caírem, ele também cai
        self.skipped = None
        self.result = None


class Plan:
    def __init__(self, known):
        self.actions = []
        self.ops = {}
        self.known = known
        self.chave_of = {}
        self.manuais = []
        self.share_problem = self.mask_status = self.masked = None  # preenchidos por build_plan (enable-detokenize)
        self.extras = {}
        self.notas = []

    def add(self, a):
        self.actions.append(a)
        self.ops[(a.kind, a.nome)] = a.op
        return a

    def count(self):
        c = {}
        for a in self.actions:
            c[a.op] = c.get(a.op, 0) + 1
        return c

    def pending_writes(self):
        return [a for a in self.actions if a.op in ("CRIAR", "ATUALIZAR") and not a.skipped]


def _diff(desired, actual, fields, skip=()):
    out = []
    for f in fields:
        if f in skip or desired.get(f) is None:
            continue
        a = actual.get(f)
        if f == "prefix":
            a = a or ""
        if a != desired[f]:
            out.append((f, a, desired[f]))
    return out


def _key_users(D, idx, chave, exceto):
    """Tokengroups, além de `exceto`, que usam a chave: os do vault e os DECLARADOS no arquivo."""
    users = {n for n, t in idx["tokengroups"].items() if n != exceto and t["chave"] == chave}
    users |= {n for n, t in D.items["tokengroups"].items() if n != exceto and t.get("chave") == chave}
    return sorted(users)


def _group_detokenize(state, refs, grupo):
    """Texto explicando por que o grupo JÁ concede detokenize no vault; '' se não concede."""
    for r in state.raw["permissoes_grupos"]:
        name, resolved = refs.to_name("perm_group.group", r.get("group"))
        if not resolved:
            return "tem permissões que não consegui atribuir a um grupo (referência perm_group.group a confirmar)"
        if name == grupo and r.get("canGet"):
            return "já tem canGet=true no vault"
    return ""


def _detail(D, kind, obj_id):
    p = DETAIL_PATH[kind].format(id=obj_id)
    return p + "/" if D.api.get("detail_trailing_slash") else p


def build_plan(D, state, refs, opts=None):
    opts = opts or {}
    env = opts.get("env", os.environ)
    allow_breaking = opts.get("allow_breaking_update", False)
    N = normalize(state, refs, D.convencao)
    idx = {k: {x["nome"]: x for x in N[k]} for k in
           ("chaves", "charsets", "grupos", "mascaras", "tokengroups", "templates", "usuarios")}
    raw = {k: state.by_name(k) for k in idx}
    P = Plan(state.known)
    if not state.known:
        P.notas.append("estado do vault NÃO consultado (offline sem --state-dir): tudo que não está "
                       "declarado no arquivo aparece como a verificar e todo item declarado como CRIAR")

    def dep(kind, nome):
        if nome in idx[kind] and P.ops.get((kind, nome)) != "BLOQUEADO":
            return True
        if P.ops.get((kind, nome)) in ("CRIAR", "ATUALIZAR", "OK", "CONFLITO", "MANUAL"):
            return True
        if not state.known and nome not in D.items.get(kind, {}):
            return True
        return False

    # ------------------------------------------------------------------ chaves
    for nome in D.names("chaves"):
        it = D.items["chaves"][nome]
        if nome in idx["chaves"]:
            d = _diff(it, idx["chaves"][nome], ["seedkey"])
            a = Action("chaves", nome, "CONFLITO" if d else "OK",
                       ["seedkey difere; alterar a chave semente não é feito automaticamente"] if d else [])
            a.diffs = d
        else:
            a = Action("chaves", nome, "CRIAR")
            a.method, a.path = "POST", RAW_PATHS["chaves"]
            a.build = (lambda it: lambda r, s: {"name": it["nome"], **(
                {"seedkey": it["seedkey"]} if "seedkey" in it else {})})(it)
            a.motivo = ["o cofre gera o material da chave; confirme com a equipe do vault antes"]
        P.add(a)

    # ------------------------------------------------------------------ charsets
    for nome in D.names("charsets"):
        it = D.items["charsets"][nome]
        if nome in idx["charsets"]:
            cur = idx["charsets"][nome]
            d = [] if cur["predefined"] else _diff(it, cur, ["alphabet", "range"])
            a = Action("charsets", nome, "CONFLITO" if d else "OK",
                       ["muda o alfabeto de um charset existente"] if d else [])
            a.diffs = d
        elif not it.get("alphabet"):
            a = Action("charsets", nome, "BLOQUEADO", ["charset customizado sem 'alphabet'"])
        else:
            a = Action("charsets", nome, "CRIAR")
            a.method, a.path = "POST", RAW_PATHS["charsets"]
            a.build = (lambda it: lambda r, s: {"name": it["nome"], "alphabet": it["alphabet"],
                                                "range": it["range"], "predefined": False})(it)
        P.add(a)

    # ------------------------------------------------------------------ grupos
    for nome in D.names("grupos"):
        if nome in idx["grupos"]:
            a = Action("grupos", nome, "OK")
        else:
            a = Action("grupos", nome, "CRIAR")
            a.method, a.path = "POST", RAW_PATHS["grupos"]
            a.build = (lambda n: lambda r, s: {"name": n})(nome)
        P.add(a)

    # ------------------------------------------------------------------ tokengroups
    for nome in D.names("tokengroups"):
        it = D.items["tokengroups"][nome]
        chave = it.get("chave")
        cur = idx["tokengroups"].get(nome)
        if chave is None and cur is not None:
            chave = cur["chave"]
        P.chave_of[nome] = chave
        if cur is not None:
            a = Action("tokengroups", nome, "OK")
            if it.get("chave") is not None:
                if refs.mode("tokengroup.key")[0] is None:
                    a.motivo.append("chave não comparada: formato da referência a confirmar (probe-refs)")
                elif cur["chave"] != it["chave"]:
                    a.op = "CONFLITO"
                    a.diffs = [("chave", cur["chave"], it["chave"])]
                    a.motivo.append("trocar a chave de um tokengroup existente invalida tokens já gerados")
        elif chave is None:
            a = Action("tokengroups", nome, "BLOQUEADO", ["chave do tokengroup não declarada (campo 'chave' ou --key-map GRUPO=CHAVE) e ele não existe no vault"])
        elif not dep("chaves", chave):
            a = Action("tokengroups", nome, "BLOQUEADO", ["chave '%s' não existe nem está declarada" % chave])
        elif _key_users(D, idx, chave, nome) and not it.get("chave_compartilhada"):
            a = Action("tokengroups", nome, "BLOQUEADO", [
                "chave '%s' já é usada pelo(s) tokengroup(s) %s: permissão é por CHAVE, então este tokengroup "
                "herdaria o acesso do outro. Para compartilhar de propósito, declare 'chave_compartilhada: true'"
                % (chave, ", ".join(_key_users(D, idx, chave, nome)))])
        else:
            a = Action("tokengroups", nome, "CRIAR")
            a.method, a.path = "POST", RAW_PATHS["tokengroups"]
            a.refs_needed = ["tokengroup.key"]
            a.deps = [("chaves", chave)]
            a.build = (lambda n, c: lambda r, s: {"name": n, "key": r.to_api("tokengroup.key", c)})(nome, chave)
        P.add(a)

    # ------------------------------------------------------------------ templates
    formats = set(N["formats"])
    for nome in D.names("templates"):
        it = D.items["templates"][nome]
        bl = list(it.get("bloqueios") or [])
        if not dep("tokengroups", it["tokengroup"]):
            bl.append("tokengroup '%s' não existe nem está declarado" % it["tokengroup"])
        if it.get("charset") and not dep("charsets", it["charset"]):
            bl.append("charset '%s' não existe no vault nem está declarado" % it["charset"])
        if formats and it["format"] not in formats:
            bl.append("format '%s' não está entre os formatos do vault (%s)" % (it["format"], ", ".join(sorted(formats))))
        if bl:
            P.add(Action("templates", nome, "BLOQUEADO", bl))
            continue
        cur = idx["templates"].get(nome)
        if cur is not None:
            skip = {f for f, rf in TEMPLATE_REF.items() if refs.mode(rf)[0] is None}
            d = _diff(it, cur, TEMPLATE_COMPARE, skip)
            a = Action("templates", nome, "OK")
            if skip:
                a.motivo.append("não comparado (formato a confirmar): %s" % ", ".join(sorted(skip)))
            if d:
                a.diffs = d
                if allow_breaking:
                    a.op = "ATUALIZAR"
                    a.method, a.path = "PUT", _detail(D, "templates", raw["templates"][nome].get(ID_FIELD["templates"]))
                    a.motivo.append("--allow-breaking-update: muda a receita; tokens existentes podem deixar de detokenizar")
                else:
                    a.op = "CONFLITO"
                    a.motivo.append("muda a receita de um template existente (tokens existentes ficam inválidos); "
                                    "só com --allow-breaking-update")
        else:
            a = Action("templates", nome, "CRIAR")
            a.method, a.path = "POST", RAW_PATHS["templates"]
        if a.op in ("CRIAR", "ATUALIZAR"):
            a.refs_needed = list(TEMPLATE_REF.values())
            a.deps = [("tokengroups", it["tokengroup"])]

            def b(t):
                def f(r, s):
                    p = {"name": t["nome"], "tenant": r.to_api("template.tenant", t["tokengroup"]),
                         "format": r.to_api("template.format", t["format"]),
                         "charset": r.to_api("template.charset", t["charset"]),
                         "keepleft": t["keep_left"], "keepright": t["keep_right"],
                         "irreversible": t["irreversible"], "allowsmallinput": t["allow_small_input"],
                         "copyruntdata": t["preserve_null_or_1_char"], "prefix": t["prefix"]}
                    for k, rk in (("start_year", "startyear"), ("end_year", "endyear"),
                                  ("date_record_count", "daterecordcount"), ("date_table_num", "datetablenum")):
                        if k in t:
                            p[rk] = t[k]
                    return p
                return f
            a.build = b(it)
        P.add(a)

    # ------------------------------------------------------------------ máscaras
    for nome in D.names("mascaras"):
        it = D.items["mascaras"][nome]
        if it.get("bloqueios"):
            P.add(Action("mascaras", nome, "BLOQUEADO", it["bloqueios"]))
            continue
        cur = idx["mascaras"].get(nome)
        body = (lambda m: lambda r, s: {"name": m["nome"], "showleft": m["show_left"],
                                        "showright": m["show_right"], "maskchar": m["mask_char"]})(it)
        if cur is None:
            a = Action("mascaras", nome, "CRIAR")
            a.method, a.path, a.build = "POST", RAW_PATHS["mascaras"], body
        else:
            d = _diff(it, cur, ["show_left", "show_right", "mask_char"])
            if d:
                a = Action("mascaras", nome, "ATUALIZAR", ["muda o que usuários com esta máscara enxergam"])
                a.diffs = d
                a.method, a.path = "PUT", _detail(D, "mascaras", raw["mascaras"][nome].get(ID_FIELD["mascaras"]))
                a.build = body
            else:
                a = Action("mascaras", nome, "OK")
        P.add(a)

    # ------------------------------------------------------------------ usuários
    perms_of = {}
    for pnome in D.names("permissoes_usuarios"):
        perms_of.setdefault(D.items["permissoes_usuarios"][pnome]["usuario"], []).append(
            ("permissoes_usuarios", pnome))
    for nome in D.names("usuarios"):
        it = D.items["usuarios"][nome]
        bl = list(it.get("bloqueios") or [])
        pw_problem = password_var_problem(it["password_ref"][4:])
        if pw_problem:
            bl.append(pw_problem)
        if it.get("mascara") and P.ops.get(("mascaras", it["mascara"])) == "BLOQUEADO":
            bl.append("máscara '%s' bloqueada" % it["mascara"])
        for g in it["grupos"]:
            if not dep("grupos", g):
                bl.append("grupo '%s' não existe nem está declarado" % g)
        cur = idx["usuarios"].get(nome)
        if cur is None and it.get("mascara"):
            for g in it["grupos"]:
                grant = _group_detokenize(state, refs, g)
                if grant:
                    bl.append("usuário nasce mascarado (máscara atribuída só manualmente) e o grupo '%s' %s: ele veria "
                              "o dado completo até lá. A soma de permissão grupo+usuário no CT-VL não foi confirmada "
                              "(A CONFIRMAR); tire-o do grupo ou rebaixe o canGet do grupo antes" % (g, grant))
        if bl and cur is None:
            P.add(Action("usuarios", nome, "BLOQUEADO", bl))
            continue
        if cur is not None:
            d = _diff(it, cur, ["ativo"])
            if sorted(it["grupos"]) != sorted(cur["grupos"]):
                d.append(("grupos", cur["grupos"], it["grupos"]))
            if (it["mascara"] or None) != (cur["mascara"] or None):
                d.append(("mascara", cur["mascara"], it["mascara"]))
            a = Action("usuarios", nome, "MANUAL" if d else "OK")
            a.diffs = d
        else:
            var = it["password_ref"][4:]
            a = Action("usuarios", nome, "CRIAR")
            a.method, a.path = "POST", RAW_PATHS["usuarios"]
            a.env_needed = [var]
            a.needed_by = perms_of.get(nome, [])
            a.motivo.append("senha via variável %s (%s; o valor nunca é exibido)" % (
                var, "definida" if var in env else "NÃO definida, necessária no apply"))
            if it["grupos"]:
                a.refs_needed = ["user.groups"]
            a.deps = [("grupos", g) for g in it["grupos"]]

            def ub(u, v):
                def f(r, s):
                    pw = os.environ.get(v)
                    if not pw:
                        raise CtvlError("variável de ambiente %s (senha de %s) não definida" % (v, u["nome"]))
                    p = {"username": u["nome"], "email": u["email"], "password": pw, "is_active": u["ativo"]}
                    if u["grupos"]:
                        p["groups"] = [r.to_api("user.groups", g) for g in u["grupos"]]
                    return p
                return f
            a.build = ub(it, var)
            if it["mascara"]:
                P.manuais.append("usuário %s: atribuir a máscara '%s' (campo 'mask' é somente leitura no swagger; "
                                 "não há endpoint de atribuição documentado)" % (nome, it["mascara"]))
        P.add(a)

    # ------------------------------------------------------------------ permissões de token
    # REGRA ÚNICA: o apply nunca escreve canGet=true para PERFIL MASCARADO (máscara declarada no arquivo OU
    # atribuída no vault) nem para grupo com membro mascarado. Esse canGet só vai por `ctvl enable-detokenize`.
    def masked(u):
        return bool(D.items["usuarios"].get(u, {}).get("mascara") or idx["usuarios"].get(u, {}).get("mascara"))

    def mask_status(u):
        """(confirmada, motivo): a máscara declarada é exatamente a atribuída, resolvida e existe igual no vault."""
        decl = D.items["usuarios"].get(u, {}).get("mascara")
        cu = idx["usuarios"].get(u)
        if not decl:
            return False, "o vault tem máscara atribuída que o arquivo não declara"
        if cu is None:
            return False, "usuário novo: a máscara é atribuída manualmente depois"
        if not cu["mascara"]:
            return False, "o usuário está sem máscara atribuída"
        if not refs.to_name("user.mask", raw["usuarios"][u].get("mask"))[1]:
            return False, ("a máscara atual não pôde ser resolvida (formato de user.mask a confirmar: "
                           "rode probe-refs e declare api.refs.user.mask)")
        if cu["mascara"] != decl:
            return False, "a máscara atual '%s' difere da declarada '%s'" % (cu["mascara"], decl)
        if P.ops.get(("mascaras", decl)) != "OK":
            return False, "a máscara '%s' não confere com a declarada no vault (%s)" % (decl, P.ops.get(("mascaras", decl)))
        return True, ""

    groups_unknown = refs.mode("user.groups")[0] is None and any(o.get("groups") for o in state.raw["usuarios"])

    def masked_members(g):
        users = {u for u, x in idx["usuarios"].items() if g in x["grupos"]}
        users |= {u for u, x in D.items["usuarios"].items() if g in x["grupos"]}
        if groups_unknown:
            users |= set(idx["usuarios"]) | set(D.items["usuarios"])
        return sorted(u for u in users if masked(u))

    def opt_in(tgname):
        return bool(D.items["tokengroups"].get(tgname, {}).get("chave_compartilhada"))

    def share_problem(tg, chave):
        if tg:
            others = _key_users(D, idx, chave, tg)
            if others and not opt_in(tg):
                return ("chave '%s' também é usada pelo(s) tokengroup(s) %s, não só por '%s': a permissão daria "
                        "acesso a outro sistema (opt-in: 'chave_compartilhada: true' no tokengroup)"
                        % (chave, ", ".join(others), tg))
            return None
        users = _key_users(D, idx, chave, None)
        if len(users) > 1 and not all(opt_in(u) for u in users):
            return ("chave '%s' é usada por mais de um tokengroup (%s) e nem todos declaram 'chave_compartilhada: "
                    "true': permissão é por CHAVE e daria acesso a todos eles" % (chave, ", ".join(users)))
        return None

    habilitar = {}   # usuário mascarado com detokenize declarado que ainda depende do enable-detokenize
    grupos_mask = {}  # grupo -> membros mascarados (permissão de grupo fica canGet=false)
    for kind, subj, fkey, subj_kind in (("permissoes_usuarios", "usuario", "perm_user", "usuarios"),
                                        ("permissoes_grupos", "grupo", "perm_group", "grupos")):
        rows = state.raw[kind]
        sf = "user" if subj == "usuario" else "group"
        for nome in D.names(kind):
            it = D.items[kind][nome]
            chave = it.get("chave") or P.chave_of.get(it.get("tokengroup"))
            if not chave:
                P.add(Action(kind, nome, "BLOQUEADO", ["chave do tokengroup '%s' desconhecida" % it.get("tokengroup")]))
                continue
            bl = []
            tg = it.get("tokengroup")
            if P.ops.get((subj_kind, it[subj])) == "BLOQUEADO":
                bl.append("%s '%s' está bloqueado" % (subj, it[subj]))
            elif not dep(subj_kind, it[subj]):
                bl.append("%s '%s' não existe nem está declarado" % (subj, it[subj]))
            if not dep("chaves", chave):
                bl.append("chave '%s' não existe nem está declarada" % chave)
            cur_tg = idx["tokengroups"].get(tg) if tg else None
            dec_tg = D.items["tokengroups"].get(tg, {}) if tg else {}
            if cur_tg is not None:
                # tokengroup existente: a chave (declarada, herdada ou da permissão) é SEMPRE comparada com a real
                if refs.mode("tokengroup.key")[0] is None:
                    bl.append("chave do tokengroup '%s' não comparável (formato da referência a confirmar): "
                              "declare api.refs.tokengroup.key (rode probe-refs)" % tg)
                elif cur_tg["chave"] != chave:
                    bl.append("chave '%s' difere da chave atual '%s' do tokengroup '%s' no vault: a permissão "
                              "daria acesso a outra chave" % (chave, cur_tg["chave"], tg))
            elif tg and dec_tg.get("chave") and it.get("chave") and it["chave"] != dec_tg["chave"]:
                bl.append("chave '%s' difere da chave declarada '%s' para o tokengroup '%s': a permissão daria "
                          "acesso a outra chave" % (chave, dec_tg["chave"], tg))
            if bl:
                P.add(Action(kind, nome, "BLOQUEADO", bl))
                continue
            if rows and (refs.mode(fkey + ".key")[0] is None or refs.mode(fkey + "." + sf)[0] is None):
                P.add(Action(kind, nome, "BLOQUEADO",
                             ["permissões existentes com referências em formato a confirmar (rode probe-refs e declare api.refs)"]))
                continue
            match = [r for r in rows
                     if refs.to_name(fkey + "." + sf, r.get(sf))[0] == it[subj]
                     and refs.to_name(fkey + ".key", r.get("key"))[0] == chave]
            cur_get = bool(match[0].get("canGet")) if len(match) == 1 else False
            can_get, nota = bool(it["detokenize"]), None
            if kind == "permissoes_usuarios" and masked(it[subj]):
                ok_mask, why = mask_status(it[subj])
                # perfil mascarado: nunca sobe para true; só mantém um true que o enable-detokenize já escreveu
                can_get = (cur_get and bool(it["detokenize"])) if ok_mask else False
                if it["detokenize"] and not can_get:
                    habilitar[it[subj]] = why
                    nota = "perfil mascarado: canGet=false%s; só `ctvl enable-detokenize` escreve true" % (
                        " (%s)" % why if why else "")
            elif kind == "permissoes_grupos":
                mm = masked_members(it[subj])
                if mm:
                    can_get = False
                    if it["detokenize"]:
                        grupos_mask[it[subj]] = mm
                        nota = "grupo com membro(s) mascarado(s) (%s): canGet=false" % ", ".join(mm)
            want = {"canPost": it["tokenize"], "canGet": can_get}
            deps = [(subj_kind, it[subj]), ("chaves", chave)]
            if tg:
                deps.append(("tokengroups", tg))  # tokengroup em CONFLITO/BLOQUEADO leva a permissão junto

            def pb(it_, chave_, subj_key, sf_, fk_, can_get_):
                def f(r, s):
                    return {sf_: r.to_api(fk_ + "." + sf_, it_[subj_key]),
                            "key": r.to_api(fk_ + ".key", chave_),
                            "canPost": it_["tokenize"], "canGet": can_get_}
                return f
            if len(match) > 1:
                a = Action(kind, nome, "CONFLITO", ["%d linhas de permissão para o mesmo par; resolva na GUI" % len(match)])
            elif match:
                cur = match[0]
                d = [(k, bool(cur.get(k)), v) for k, v in want.items() if bool(cur.get(k)) != v]
                a = Action(kind, nome, "ATUALIZAR" if d else "OK")
                a.diffs = d
                if d:
                    a.method, a.path = "PUT", _detail(D, kind, cur.get(ID_FIELD[kind]))
                    a.build = pb(it, chave, subj, sf, fkey, can_get)
                    a.refs_needed = [fkey + "." + sf, fkey + ".key"]
                    a.deps = deps
            else:
                a = Action(kind, nome, "CRIAR")
                a.method, a.path = "POST", RAW_PATHS[kind]
                a.build = pb(it, chave, subj, sf, fkey, can_get)
                a.refs_needed = [fkey + "." + sf, fkey + ".key"]
                a.deps = deps
            if a.op in ("CRIAR", "ATUALIZAR"):
                subiu = (a.op == "CRIAR" and (want["canPost"] or want["canGet"])) or \
                    any(new and not old for _, old, new in a.diffs)
                prob = share_problem(tg, chave) if subiu else None  # rebaixar nunca é bloqueado
                if prob:
                    P.add(Action(kind, nome, "BLOQUEADO", [prob]))
                    continue
            a.motivo.append("permissão é sobre a CHAVE '%s' (vale para todo tokengroup que a use)" % chave)
            if nota:
                a.motivo.append(nota)
            P.add(a)
    P.share_problem, P.mask_status, P.masked = share_problem, mask_status, masked
    for u in sorted(habilitar):
        P.manuais.append("usuário %s: HABILITAR DETOKENIZE pendente: rode `ctvl enable-detokenize <ambiente> %s "
                         "--file <arquivo>` (a permissão fica canGet=false até lá; motivo atual: %s)"
                         % (u, u, habilitar[u] or "máscara ainda não verificada pelo enable-detokenize"))
    for g in sorted(grupos_mask):
        P.manuais.append("grupo %s: a permissão do grupo fica canGet=false porque há membro(s) mascarado(s) (%s); "
                         "a skill não habilita detokenize de grupo com mascarado: tire-os do grupo ou habilite "
                         "fora da skill" % (g, ", ".join(grupos_mask[g])))
    for r in state.raw["permissoes_grupos"]:  # grupo que JÁ concede no vault e não é gerido pelo arquivo
        gname, ok_ref = refs.to_name("perm_group.group", r.get("group"))
        mm = masked_members(gname) if ok_ref and r.get("canGet") and gname not in grupos_mask else []
        if mm and not any(p["grupo"] == gname for p in D.items["permissoes_grupos"].values()):
            P.manuais.append("grupo %s: já tem canGet=true no vault e membro(s) mascarado(s) (%s); a skill não "
                             "altera permissões de grupo fora do arquivo" % (gname, ", ".join(mm)))

    # extras (nunca removidos)
    managed = {"chaves": "chaves", "charsets": "charsets", "grupos": "grupos", "tokengroups": "tokengroups",
               "templates": "templates", "mascaras": "mascaras", "usuarios": "usuarios"}
    for kind in managed:
        extra = sorted(n for n in idx[kind] if n not in D.items[kind]
                       and not (kind == "charsets" and idx[kind][n].get("predefined")))
        if extra:
            P.extras[kind] = extra
    return P


def finalize(P, skip_blocked=False):
    """Marca como puladas as ações cujas dependências não serão aplicadas."""
    not_applied = {(a.kind, a.nome) for a in P.actions if a.op in ("BLOQUEADO", "CONFLITO")}
    for a in P.actions:
        if a.op in ("CRIAR", "ATUALIZAR"):
            bad = [d for d in a.deps if d in not_applied]
            if bad:
                a.skipped = "depende de %s não aplicado" % ", ".join("%s '%s'" % (LABEL[k], n) for k, n in bad)
                not_applied.add((a.kind, a.nome))
    # usuário a criar que só existe para dar permissões: se nenhuma delas será aplicada, ele também não
    for a in P.actions:
        if a.op == "CRIAR" and not a.skipped and a.needed_by and all(d in not_applied for d in a.needed_by):
            a.skipped = "todas as suas permissões (%s) estão bloqueadas ou puladas" % ", ".join(
                "%s '%s'" % (LABEL[k], n) for k, n in a.needed_by)
            not_applied.add((a.kind, a.nome))
    return P


def render(P, show_extra=False):
    L = []
    for n in P.notas:
        L.append("# nota: " + n)
    L.append("%-10s %-12s %-34s %s" % ("OPERAÇÃO", "TIPO", "NOME", "DETALHE"))
    for a in sorted(P.actions, key=lambda x: (ORDER.index(x.kind), x.nome)):
        det = "; ".join(a.motivo)
        if a.skipped:
            det = ("PULADO: " + a.skipped + ("; " + det if det else ""))
        L.append("%-10s %-12s %-34s %s" % (a.op, LABEL[a.kind], a.nome, det))
        for f, cur, new in a.diffs:
            L.append("%-10s %-12s %-34s   %s: %r -> %r" % ("", "", "", f, cur, new))
    c = P.count()
    L.append("")
    L.append("Resumo: " + ", ".join("%s=%d" % (k, c[k]) for k in
                                   ("CRIAR", "ATUALIZAR", "OK", "MANUAL", "CONFLITO", "BLOQUEADO") if k in c) or "vazio")
    if P.manuais:
        L.append("")
        L.append("Pendências manuais (a skill não executa):")
        for m in P.manuais:
            L.append("  - " + m)
    if show_extra and P.extras:
        L.append("")
        L.append("No vault e fora do arquivo (NUNCA removidos por esta skill):")
        for k, names in P.extras.items():
            L.append("  %s: %s" % (LABEL[k], ", ".join(names)))
    return mask_text("\n".join(L))


def preflight(P, refs, env=None):
    """Falha ANTES de qualquer escrita: referências não confirmadas e senhas ausentes."""
    env = env if env is not None else os.environ
    probs = []
    for a in P.pending_writes():
        for f in a.refs_needed:
            try:
                refs.write_mode(f)
            except RefUnconfirmed as e:
                msg = str(e)
                if msg not in probs:
                    probs.append(msg)
        for v in a.env_needed:
            if not env.get(v):
                m = "variável de ambiente %s (senha do usuário %s) não definida" % (v, a.nome)
                if m not in probs:
                    probs.append(m)
    return probs


def apply_plan(P, D, client, state, refs, out):
    """Executa CRIAR/ATUALIZAR em ordem. Para no primeiro erro. out(texto) imprime."""
    done = 0
    for a in sorted(P.actions, key=lambda x: ORDER.index(x.kind)):
        if a.op not in ("CRIAR", "ATUALIZAR"):
            continue
        if a.skipped:
            out("PULADO   %s %s: %s" % (LABEL[a.kind], a.nome, a.skipped))
            continue
        try:
            body = a.build(refs, state)
        except (RefUnconfirmed, ValueError, CtvlError) as e:
            raise CtvlError("%s %s: %s" % (LABEL[a.kind], a.nome, e))
        out("EXECUTA  %s %s %s  corpo=%s" % (a.method, a.path, "(%s %s)" % (LABEL[a.kind], a.nome),
                                              mask_obj(body)))
        st, data = client.request(a.method, a.path, body=body)
        if not 200 <= st < 300:
            raise HttpFailure(st, a.method, a.path, data)
        a.result = st
        if isinstance(data, dict) and a.method == "POST":
            state.add(a.kind, data)
        done += 1
        out("  -> HTTP %s" % st)
    return done


def verify_after(D, client, opts):
    st2 = load_state(client)
    refs2 = Refs(st2, D.api["refs"])
    P2 = finalize(build_plan(D, st2, refs2, opts))
    return [a for a in P2.actions if a.op in ("CRIAR", "ATUALIZAR")]
