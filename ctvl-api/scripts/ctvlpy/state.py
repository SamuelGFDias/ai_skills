"""Estado atual do vault, referências (nome x id) e normalização para o modelo da skill."""
from .naming import parse_mask_name, parse_user_name

RAW_PATHS = {
    "chaves": "/keys/", "charsets": "/charsets/", "grupos": "/groups/", "tokengroups": "/tokengroups/",
    "templates": "/tokentemplates/", "mascaras": "/masks/", "usuarios": "/users/",
    "permissoes_usuarios": "/permissions/token/users/", "permissoes_grupos": "/permissions/token/groups/",
    "formats": "/formats/",
}
NAME_FIELD = {"chaves": "name", "charsets": "name", "grupos": "name", "tokengroups": "name",
              "templates": "name", "mascaras": "name", "usuarios": "username", "formats": "name"}
ID_FIELD = {"chaves": "idkey", "charsets": "idtokencharset", "grupos": "id", "tokengroups": "idtenant",
            "templates": "idtokentemplate", "mascaras": "idmask", "usuarios": "id", "formats": "idtokenformat",
            "permissoes_usuarios": "id", "permissoes_grupos": "id"}
DETAIL_PATH = {"chaves": "/keys/{id}", "charsets": "/charsets/{id}", "grupos": "/groups/{id}",
               "tokengroups": "/tokengroups/{id}", "templates": "/tokentemplates/{id}", "mascaras": "/masks/{id}",
               "usuarios": "/users/{id}", "permissoes_usuarios": "/permissions/token/users/{id}",
               "permissoes_grupos": "/permissions/token/groups/{id}"}

# campo-referência -> (tipo dono, tipo alvo, campo bruto no JSON da API)
REF_FIELDS = {
    "tokengroup.key": ("tokengroups", "chaves", "key"),
    "template.tenant": ("templates", "tokengroups", "tenant"),
    "template.format": ("templates", "formats", "format"),
    "template.charset": ("templates", "charsets", "charset"),
    "user.groups": ("usuarios", "grupos", "groups"),
    "user.mask": ("usuarios", "mascaras", "mask"),
    "perm_user.user": ("permissoes_usuarios", "usuarios", "user"),
    "perm_user.key": ("permissoes_usuarios", "chaves", "key"),
    "perm_group.group": ("permissoes_grupos", "grupos", "group"),
    "perm_group.key": ("permissoes_grupos", "chaves", "key"),
}
# O swagger só prova um formato: `user` das permissões tem o pattern de username (^[\w.@+-]+$).
SWAGGER_CONFIRMED = {"perm_user.user": "name"}


class RefUnconfirmed(Exception):
    def __init__(self, field):
        self.field = field
        super().__init__(
            "formato da referência '%s' (nome ou id) é A CONFIRMAR: rode `ctvl.sh probe-refs <ambiente>` e "
            "declare em api.refs (ex.: api.refs.%s: name)" % (field, field))


class State:
    def __init__(self, raw, known=True):
        self.raw = {k: list(raw.get(k) or []) for k in list(RAW_PATHS)}
        self.known = known

    def by_name(self, kind):
        nf = NAME_FIELD[kind]
        return {o.get(nf): o for o in self.raw[kind] if o.get(nf) is not None}

    def names(self, kind):
        return set(self.by_name(kind))

    def add(self, kind, obj):
        self.raw[kind].append(obj)


def load_state(client):
    raw = {k: client.get_all(p) for k, p in RAW_PATHS.items()}
    return State(raw, known=True)


def empty_state():
    return State({}, known=False)


def _samples(obj_list, raw_field):
    for o in obj_list:
        v = o.get(raw_field)
        if isinstance(v, list):
            for x in v:
                yield x
        elif v not in (None, ""):
            yield v


class Refs:
    """Traduz referências entre o JSON da API (nome ou id) e nomes. Escrita só com formato confirmado."""

    def __init__(self, state, confirmed=None):
        self.state = state
        self.confirmed = dict(confirmed or {})
        self._cache = {}

    def _infer(self, field):
        owner, target, raw_field = REF_FIELDS[field]
        names = self.state.names(target)
        idf = ID_FIELD[target]
        ids = {str(o.get(idf)) for o in self.state.raw[target] if o.get(idf) is not None}
        n_name = n_id = 0
        for v in _samples(self.state.raw[owner], raw_field):
            s = str(v)
            in_n, in_i = s in names, s in ids
            if in_n and in_i:
                continue  # ambíguo: não conta como evidência
            if in_n:
                n_name += 1
            elif in_i:
                n_id += 1
            else:
                return None, n_name + n_id  # valor que não é nome nem id conhecido: inconclusivo
        if n_name and not n_id:
            return "name", n_name
        if n_id and not n_name:
            return "id", n_id
        return None, n_name + n_id

    def mode(self, field):
        """(modo, origem). origem: confirmado | swagger | evidência | None."""
        if field in self.confirmed:
            return self.confirmed[field], "confirmado"
        if field in SWAGGER_CONFIRMED:
            return SWAGGER_CONFIRMED[field], "swagger"
        if field not in self._cache:
            self._cache[field] = self._infer(field)
        m, _ = self._cache[field]
        return (m, "evidência") if m else (None, None)

    def evidence(self, field):
        if field not in self._cache:
            self._cache[field] = self._infer(field)
        return self._cache[field]

    def write_mode(self, field):
        """Modo para ESCRITA: só confirmado/swagger; senão levanta RefUnconfirmed."""
        if field in self.confirmed:
            return self.confirmed[field]
        if field in SWAGGER_CONFIRMED:
            return SWAGGER_CONFIRMED[field]
        raise RefUnconfirmed(field)

    def to_name(self, field, raw):
        """(nome, resolvido). resolvido=False quando o formato não é conhecido."""
        if raw in (None, ""):
            return None, True
        mode, _ = self.mode(field)
        target = REF_FIELDS[field][1]
        if mode == "name":
            return str(raw), True
        if mode == "id":
            idf, nf = ID_FIELD[target], NAME_FIELD[target]
            for o in self.state.raw[target]:
                if str(o.get(idf)) == str(raw):
                    return o.get(nf), True
            return "id:%s" % raw, False
        return str(raw), False

    def to_api(self, field, name):
        if name in (None, ""):
            return None
        mode = self.write_mode(field)
        if mode == "name":
            return name
        target = REF_FIELDS[field][1]
        o = self.state.by_name(target).get(name)
        if o is None or o.get(ID_FIELD[target]) is None:
            raise ValueError("não achei o id de %s '%s' para a referência %s" % (target, name, field))
        return o[ID_FIELD[target]]


def _tf(v):
    return bool(v) if v is not None else None


def normalize(state, refs, convencao=None):
    """Estado bruto -> listas normalizadas (ordenadas) no vocabulário da skill, sem ids nem segredos."""
    sist = (convencao or {}).get("sistemas")
    dts = (convencao or {}).get("datatypes")
    out = {}
    out["chaves"] = sorted(
        ({"nome": o["name"], **({"seedkey": bool(o["seedkey"])} if o.get("seedkey") is not None else {})}
         for o in state.raw["chaves"]), key=lambda x: x["nome"])
    out["charsets"] = sorted(
        ({"nome": o["name"], "predefined": bool(o.get("predefined")), "alphabet": o.get("alphabet"),
          "range": bool(o.get("range"))} for o in state.raw["charsets"]), key=lambda x: x["nome"])
    out["grupos"] = sorted(({"nome": o["name"]} for o in state.raw["grupos"]), key=lambda x: x["nome"])
    out["mascaras"] = sorted(
        ({"nome": o["name"], "show_left": o.get("showleft"), "show_right": o.get("showright"),
          "mask_char": o.get("maskchar")} for o in state.raw["mascaras"]), key=lambda x: x["nome"])
    out["tokengroups"] = sorted(
        ({"nome": o["name"], "chave": refs.to_name("tokengroup.key", o.get("key"))[0]}
         for o in state.raw["tokengroups"]), key=lambda x: x["nome"])
    tpls = []
    for o in state.raw["templates"]:
        t = {"nome": o["name"], "tokengroup": refs.to_name("template.tenant", o.get("tenant"))[0],
             "format": refs.to_name("template.format", o.get("format"))[0],
             "charset": refs.to_name("template.charset", o.get("charset"))[0],
             "keep_left": o.get("keepleft"), "keep_right": o.get("keepright"),
             "irreversible": _tf(o.get("irreversible")), "allow_small_input": _tf(o.get("allowsmallinput")),
             "preserve_null_or_1_char": _tf(o.get("copyruntdata")), "prefix": o.get("prefix") or ""}
        for k, rk in (("start_year", "startyear"), ("end_year", "endyear"),
                      ("date_record_count", "daterecordcount"), ("date_table_num", "datetablenum")):
            if o.get(rk) is not None:
                t[k] = o[rk]
        tpls.append(t)
    out["templates"] = sorted(tpls, key=lambda x: x["nome"])
    users = []
    for o in state.raw["usuarios"]:
        nome = o["username"]
        meta = parse_user_name(nome, sist, dts)
        groups = [refs.to_name("user.groups", g)[0] for g in (o.get("groups") or [])]
        mk = o.get("mask")
        u = {"nome": nome, "email": o.get("email"), "ativo": bool(o.get("is_active", True)),
             "grupos": sorted(g for g in groups if g),
             "mascara": refs.to_name("user.mask", mk)[0] if mk not in (None, "") else None}
        if meta["conforme"]:
            u["convencao_nome"] = {"sistema": meta["sistema"], "datatype": meta["datatype"], "esquema": meta["esquema"]}
        else:
            u["fora_do_padrao"] = list(meta["problemas"])
        users.append(u)
    out["usuarios"] = sorted(users, key=lambda x: x["nome"])
    for kind, subj, raw_subj, fkey in (("permissoes_usuarios", "usuario", "user", "perm_user"),
                                       ("permissoes_grupos", "grupo", "group", "perm_group")):
        perms = []
        for o in state.raw[kind]:
            p = {subj: refs.to_name(fkey + "." + raw_subj, o.get(raw_subj))[0],
                 "chave": refs.to_name(fkey + ".key", o.get("key"))[0],
                 "tokenize": bool(o.get("canPost")), "detokenize": bool(o.get("canGet"))}
            if o.get("asymkey"):
                p["asymkey"] = o["asymkey"]
            if o.get("opaqueobj"):
                p["opaqueobj"] = o["opaqueobj"]
            perms.append(p)
        out[kind] = sorted(perms, key=lambda x: (str(x[subj]), str(x["chave"])))
    out["formats"] = sorted(o["name"] for o in state.raw["formats"])
    return out
