"""Carrega a configuração declarativa (YAML) e a expande no modelo plano "Desired".

Duas formas de entrada, que se combinam:
  - autoria: `defaults` + `sistemas` (com overrides) + `convencao`;
  - plana  : `recursos` (o mesmo formato que o `export` gera).
Modo legado: --docs-dir lê os YAMLs de docs/tokenizacao-ctvl/ (templates, usuários e máscaras).
Nunca lê senhas: `password_ref` só aponta (env:NOME). O que ainda não foi decidido vira bloqueio.
"""
import os

import yaml

from .naming import (DEFAULT_DATATYPES, DEFAULT_SISTEMAS, RESERVED_SVC, build_user_name,
                     env_var_for, parse_mask_name, parse_user_name, password_var_problem)


class ConfigError(Exception):
    pass


KINDS = ["chaves", "charsets", "grupos", "tokengroups", "templates", "mascaras",
         "usuarios", "permissoes_usuarios", "permissoes_grupos"]

TOP_KEYS = {"versao", "gerado_por", "ambiente", "convencao", "api", "usuarios_padrao",
            "defaults", "sistemas", "recursos", "nota"}
IGNORED_DOC_KEYS = {"observacao", "uso", "nota", "finalidade", "aplica_se_a_templates", "status",
                    "convencao_nome", "fora_do_padrao"}

TEMPLATE_ALIASES = {"allow_small_inputs": "allow_small_input", "keepleft": "keep_left",
                    "keepright": "keep_right", "character_set": "charset", "token_group": "tokengroup"}
TEMPLATE_DEFAULTS = {"keep_left": 0, "keep_right": 0, "irreversible": False, "allow_small_input": False,
                     "preserve_null_or_1_char": False, "prefix": ""}
TEMPLATE_OPTIONAL = ["start_year", "end_year", "date_record_count", "date_table_num"]
TEMPLATE_FIELDS = (set(TEMPLATE_DEFAULTS) | set(TEMPLATE_OPTIONAL) |
                   {"nome", "tokengroup", "format", "charset"})
PENDING_WORDS = ("PENDENTE", "A_CONFIRMAR", "A CONFIRMAR", "TODO")


class Desired:
    def __init__(self):
        self.items = {k: {} for k in KINDS}
        self.warnings = []
        self.convencao = {"sistemas": list(DEFAULT_SISTEMAS), "datatypes": list(DEFAULT_DATATYPES)}
        self.api = {"refs": {}, "detail_trailing_slash": False}
        self.accept_suggestions = False

    def add(self, kind, nome, item):
        cur = self.items[kind].get(nome)
        if cur is not None and cur != item:
            raise ConfigError("%s '%s' definido mais de uma vez com conteúdo diferente" % (kind, nome))
        self.items[kind][nome] = item

    def names(self, kind):
        return sorted(self.items[kind])


def load_yaml(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except OSError as e:
        raise ConfigError("não consegui ler %s: %s" % (path, e))
    except yaml.YAMLError as e:
        raise ConfigError("YAML inválido em %s: %s" % (path, e))
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ConfigError("%s: a raiz precisa ser um mapa" % path)
    return data


def _is_pending(v):
    return v is None or (isinstance(v, str) and (not v.strip() or any(w in v.upper() for w in PENDING_WORDS)))


def _bool(v, campo):
    if isinstance(v, bool):
        return v
    raise ConfigError("%s deve ser true/false (veio %r)" % (campo, v))


def _int(v, campo):
    if isinstance(v, int) and not isinstance(v, bool) and v >= 0:
        return v
    raise ConfigError("%s deve ser inteiro >= 0 (veio %r)" % (campo, v))


# ----------------------------------------------------------------------------- máscaras

def norm_mask(params, rotulo, D):
    """params -> {'show_left','show_right','mask_char','bloqueios'} (ou None = sem máscara)."""
    if params is None:
        return None
    if not isinstance(params, dict):
        raise ConfigError("máscara %s: esperado mapa ou null" % rotulo)
    p = dict(params)
    if "keep_left" in p and "show_left" not in p:
        p["show_left"] = p.pop("keep_left")
    if "keep_right" in p and "show_right" not in p:
        p["show_right"] = p.pop("keep_right")
    bloqueios = []
    status = p.pop("status", None)
    if status and "CONFIRMAR" in str(status).upper() and not D.accept_suggestions:
        bloqueios.append("máscara pendente de confirmação (status: %s); use --accept-suggestions "
                         "para aceitar a sugestão" % status)
    for k in list(p):
        if k in IGNORED_DOC_KEYS:
            p.pop(k)
    extra = set(p) - {"show_left", "show_right", "mask_char"}
    if extra:
        raise ConfigError("máscara %s: campos desconhecidos %s" % (rotulo, sorted(extra)))
    for k in ("show_left", "show_right", "mask_char"):
        if k not in p:
            raise ConfigError("máscara %s: falta '%s'" % (rotulo, k))
    mc = p["mask_char"]
    if not isinstance(mc, str) or not mc:
        raise ConfigError("máscara %s: mask_char deve ser texto não vazio" % rotulo)
    return {"show_left": _int(p["show_left"], rotulo + ".show_left"),
            "show_right": _int(p["show_right"], rotulo + ".show_right"),
            "mask_char": mc, "bloqueios": bloqueios}


def _add_mask(D, nome, params):
    if params is None:
        return
    keys = ("show_left", "show_right", "mask_char")
    cur = D.items["mascaras"].get(nome)
    if cur is not None:
        if any(cur[k] != params[k] for k in keys):
            raise ConfigError("máscara '%s' definida com parâmetros diferentes em dois lugares" % nome)
        cur["bloqueios"] = sorted(set(cur["bloqueios"]) | set(params["bloqueios"]))
        return
    D.items["mascaras"][nome] = {"nome": nome, **params}
    pm = parse_mask_name(nome, D.convencao["sistemas"], D.convencao["datatypes"])
    if not pm["conforme"]:
        D.warnings.append("máscara '%s' fora do padrão: %s" % (nome, "; ".join(pm["problemas"])))


# ----------------------------------------------------------------------------- templates

def norm_template(raw, D, rotulo):
    t = {}
    for k, v in raw.items():
        k = TEMPLATE_ALIASES.get(k, k)
        if k in IGNORED_DOC_KEYS:
            continue
        if k not in TEMPLATE_FIELDS:
            raise ConfigError("template %s: campo desconhecido '%s'" % (rotulo, k))
        t[k] = v
    for k, v in TEMPLATE_DEFAULTS.items():
        t.setdefault(k, v)
    for k in ("nome", "tokengroup", "format"):
        if not t.get(k):
            raise ConfigError("template %s: falta '%s'" % (rotulo, k))
    t["keep_left"] = _int(t["keep_left"], rotulo + ".keep_left")
    t["keep_right"] = _int(t["keep_right"], rotulo + ".keep_right")
    for k in ("irreversible", "allow_small_input", "preserve_null_or_1_char"):
        t[k] = _bool(t[k], "%s.%s" % (rotulo, k))
    t["prefix"] = "" if t["prefix"] is None else str(t["prefix"])
    for k in TEMPLATE_OPTIONAL:
        if t.get(k) is None:
            t.pop(k, None)
        else:
            t[k] = _int(t[k], "%s.%s" % (rotulo, k))
    bl = []
    if _is_pending(t.get("charset")):
        bl.append("charset pendente de decisão do projeto (templates.yaml / README: ASCII imprimível x numérico)")
        t["charset"] = None
    t["bloqueios"] = bl
    return t


# ----------------------------------------------------------------------------- usuários

def _perm_flags(perms, rotulo):
    if not isinstance(perms, list) or not perms:
        raise ConfigError("%s: 'permissoes' deve ser lista com tokenize e/ou detokenize" % rotulo)
    bad = [p for p in perms if p not in ("tokenize", "detokenize")]
    if bad:
        raise ConfigError("%s: permissões desconhecidas %s (use tokenize, detokenize)" % (rotulo, bad))
    return "tokenize" in perms, "detokenize" in perms


def _password_ref(password_ref, nome, rotulo):
    """password_ref explícito é validado já na carga (só env:CTVL_<NOME>_PASSWORD, nunca a senha admin).

    O padrão derivado do nome NÃO é recusado aqui (um usuário chamado 'admin' deriva
    CTVL_ADMIN_PASSWORD e precisa continuar carregável); o plan bloqueia a CRIAÇÃO nesse caso.
    """
    if not password_ref:
        return "env:%s" % env_var_for(nome)
    if not (isinstance(password_ref, str) and password_ref.startswith("env:") and len(password_ref) > 4):
        raise ConfigError("%s: password_ref deve ser 'env:CTVL_<NOME>_PASSWORD' (veio %r)" % (rotulo, password_ref))
    problem = password_var_problem(password_ref[4:])
    if problem:
        raise ConfigError("%s: password_ref recusado: %s" % (rotulo, problem))
    return password_ref


def _make_user(D, nome, meta, email_dom, ativo, grupos, mascara, perms, chave, tokengroup, rotulo,
               email=None, password_ref=None):
    pr = _password_ref(password_ref, nome, rotulo)
    bl = []
    mail = email or ("%s@%s" % (nome, email_dom) if email_dom else None)
    if mail is None:
        bl.append("e-mail é obrigatório na API e não foi declarado (use usuarios_padrao.email_dominio ou email)")
    D.add("usuarios", nome, {"nome": nome, "email": mail, "ativo": ativo, "grupos": sorted(grupos or []),
                             "mascara": mascara, "password_ref": pr, "convencao_nome": meta,
                             "bloqueios": bl})
    tk, dt = _perm_flags(perms, rotulo)
    pn = "%s@%s" % (nome, chave or tokengroup)
    D.add("permissoes_usuarios", pn, {"nome": pn, "usuario": nome, "chave": chave, "tokengroup": tokengroup,
                                      "tokenize": tk, "detokenize": dt})
    for g in grupos or []:
        if g not in D.items["grupos"]:
            D.add("grupos", g, {"nome": g})


def expand_authoring(cfg, D):
    defaults = cfg.get("defaults") or {}
    dts = defaults.get("datatypes") or {}
    pad = cfg.get("usuarios_padrao") or {}
    email_dom = pad.get("email_dominio")
    ativo = _bool(pad.get("ativo", True), "usuarios_padrao.ativo")
    sistemas = cfg.get("sistemas") or {}
    conv_s, conv_d = D.convencao["sistemas"], D.convencao["datatypes"]
    for dt in dts:
        if dt not in conv_d:
            raise ConfigError("defaults.datatypes.%s fora de convencao.datatypes %s" % (dt, conv_d))

    for sname in sorted(sistemas):
        if sname not in conv_s:
            raise ConfigError("sistema '%s' fora de convencao.sistemas %s" % (sname, conv_s))
        sdef = sistemas[sname] or {}
        tg = sdef.get("tokengroup") or sname.upper()
        chave = sdef.get("chave")
        D.add("tokengroups", tg, {"nome": tg, "chave": chave, "bloqueios": [],
                                  "chave_compartilhada": _bool(sdef.get("chave_compartilhada", False),
                                                               "sistemas.%s.chave_compartilhada" % sname)})
        for dt in sdef.get("datatypes") or sorted(dts):
            if dt not in dts:
                raise ConfigError("sistema %s usa datatype '%s' sem entrada em defaults.datatypes" % (sname, dt))
            base = dts[dt] or {}
            ov = (sdef.get("overrides") or {}).get(dt) or {}
            rotulo = "%s/%s" % (sname, dt)
            tmpl = {**(base.get("template") or {}), **(ov.get("template") or {})}
            tmpl.setdefault("nome", "%s_%s" % (sname.upper(), dt.upper()))
            tmpl["tokengroup"] = tg
            t = norm_template(tmpl, D, rotulo)
            D.add("templates", t["nome"], t)

            base_m = base.get("mascaras") or {}
            ov_m = ov.get("mascaras") or {}
            eff_m = {**base_m, **ov_m}
            for k in list(eff_m):
                if not isinstance(k, str):
                    raise ConfigError("%s: nome de esquema %r não é texto (coloque entre aspas)" % (rotulo, k))

            usuarios = ov["usuarios"] if "usuarios" in ov else (base.get("usuarios") or [])
            usuarios = list(usuarios) + list(ov.get("usuarios_extra") or [])
            for u in usuarios:
                if not isinstance(u, dict):
                    raise ConfigError("%s: cada usuário deve ser um mapa" % rotulo)
                esq = u.get("esquema")
                if esq is not None and not isinstance(esq, str):
                    raise ConfigError("%s: esquema %r não é texto (coloque entre aspas)" % (rotulo, esq))
                nome = u.get("nome") or build_user_name(sname, dt, esq)
                meta = parse_user_name(nome, conv_s, conv_d)
                if not meta["conforme"] or (meta["sistema"], meta["datatype"], meta["esquema"]) != (sname, dt, esq):
                    raise ConfigError("%s: usuário '%s' não corresponde a %s_%s%s (%s)" % (
                        rotulo, nome, sname, dt, "_" + esq if esq else "", "; ".join(meta["problemas"]) or "esquema diferente"))
                esq_m = u["mascara"] if "mascara" in u else (esq if esq in eff_m else None)
                mname = None
                if esq_m is not None:
                    if esq_m not in eff_m:
                        raise ConfigError("%s: usuário %s referencia máscara '%s' fora do catálogo" % (rotulo, nome, esq_m))
                    params = norm_mask(eff_m[esq_m], "%s/%s" % (rotulo, esq_m), D)
                    if params is not None:
                        base_params = norm_mask(base_m.get(esq_m), "defaults/%s/%s" % (dt, esq_m), D) \
                            if esq_m in base_m else None
                        same = base_params is not None and \
                            {k: params[k] for k in ("show_left", "show_right", "mask_char")} == \
                            {k: base_params[k] for k in ("show_left", "show_right", "mask_char")}
                        mname = ("%s_%s" % (dt, esq_m)) if same or esq_m not in ov_m else \
                            "%s_%s_%s" % (sname, dt, esq_m)
                        _add_mask(D, mname, params)
                _make_user(D, nome, {"sistema": sname, "datatype": dt, "esquema": esq}, email_dom,
                           u.get("ativo", ativo), u.get("grupos"), mname,
                           u.get("permissoes"), chave, tg, "%s/%s" % (rotulo, nome),
                           email=u.get("email"), password_ref=u.get("password_ref"))

        servico = sdef["servico"] if "servico" in sdef else (defaults.get("servico") or [])
        for e in servico:
            esq = e.get("esquema")
            if not esq or not isinstance(esq, str):
                raise ConfigError("%s: usuário de serviço exige 'esquema' em texto" % sname)
            nome = build_user_name(sname, RESERVED_SVC, esq)
            _make_user(D, nome, {"sistema": sname, "datatype": RESERVED_SVC, "esquema": esq}, email_dom,
                       e.get("ativo", ativo), e.get("grupos"), None, e.get("permissoes"), chave, tg,
                       "%s/servico/%s" % (sname, esq), email=e.get("email"),
                       password_ref=e.get("password_ref"))


# ----------------------------------------------------------------------------- recursos planos

def _check_keys(item, allowed, rotulo):
    extra = set(item) - allowed - IGNORED_DOC_KEYS
    if extra:
        raise ConfigError("%s: campos desconhecidos %s" % (rotulo, sorted(extra)))


def load_recursos(rec, D, email_dom=None):
    if not isinstance(rec, dict):
        raise ConfigError("'recursos' deve ser um mapa")
    for k in rec:
        if k not in KINDS and k not in ("charsets_predefinidos", "ignorados"):
            raise ConfigError("recursos.%s desconhecido (válidos: %s)" % (k, ", ".join(KINDS)))
    ign = rec.get("ignorados")
    if ign is not None:
        if not isinstance(ign, dict) or not all(isinstance(v, list) for v in ign.values()):
            raise ConfigError("recursos.ignorados deve ser um mapa de listas (seção informativa do export)")
        n = sum(len(v) for v in ign.values())
        if n:
            D.warnings.append("recursos.ignorados: %d permissão(ões) informativa(s) (sem chave ou sobre "
                              "asymkey/opaqueobj) não são gerenciadas e foram ignoradas" % n)
    for c in rec.get("chaves") or []:
        _check_keys(c, {"nome", "seedkey"}, "recursos.chaves")
        D.add("chaves", c["nome"], {"nome": c["nome"], **({"seedkey": _bool(c["seedkey"], "seedkey")} if "seedkey" in c else {})})
    for c in rec.get("charsets") or []:
        _check_keys(c, {"nome", "alphabet", "range"}, "recursos.charsets")
        D.add("charsets", c["nome"], {"nome": c["nome"], "alphabet": c.get("alphabet"),
                                       "range": _bool(c.get("range", False), "range")})
    for g in rec.get("grupos") or []:
        _check_keys(g, {"nome"}, "recursos.grupos")
        D.add("grupos", g["nome"], {"nome": g["nome"]})
    for m in rec.get("mascaras") or []:
        _check_keys(m, {"nome", "show_left", "show_right", "mask_char", "keep_left", "keep_right"}, "recursos.mascaras")
        nome = m["nome"]
        _add_mask(D, nome, norm_mask({k: v for k, v in m.items() if k != "nome"}, nome, D))
    for g in rec.get("tokengroups") or []:
        _check_keys(g, {"nome", "chave", "chave_compartilhada"}, "recursos.tokengroups")
        D.add("tokengroups", g["nome"], {"nome": g["nome"], "chave": g.get("chave"), "bloqueios": [],
                                         "chave_compartilhada": _bool(g.get("chave_compartilhada", False),
                                                                      "chave_compartilhada")})
    for t in rec.get("templates") or []:
        t = norm_template(t, D, "recursos.templates")
        D.add("templates", t["nome"], t)
    for u in rec.get("usuarios") or []:
        _check_keys(u, {"nome", "email", "ativo", "grupos", "mascara", "password_ref"}, "recursos.usuarios")
        nome = u["nome"]
        meta = parse_user_name(nome, D.convencao["sistemas"], D.convencao["datatypes"])
        if not meta["conforme"]:
            D.warnings.append("usuário '%s' fora do padrão: %s" % (nome, "; ".join(meta["problemas"])))
        pr = _password_ref(u.get("password_ref"), nome, "usuário %s" % nome)
        mail = u.get("email") or ("%s@%s" % (nome, email_dom) if email_dom else None)
        bl = [] if mail else ["e-mail é obrigatório na API e não foi declarado"]
        D.add("usuarios", nome, {"nome": nome, "email": mail, "ativo": _bool(u.get("ativo", True), "ativo"),
                                 "grupos": sorted(u.get("grupos") or []), "mascara": u.get("mascara"),
                                 "password_ref": pr,
                                 "convencao_nome": {k: meta[k] for k in ("sistema", "datatype", "esquema")},
                                 "bloqueios": bl})
    n_skip = {}
    for kind, subj in (("permissoes_usuarios", "usuario"), ("permissoes_grupos", "grupo")):
        for p in rec.get(kind) or []:
            _check_keys(p, {subj, "chave", "tokengroup", "tokenize", "detokenize", "asymkey", "opaqueobj"},
                        "recursos." + kind)
            if p.get("asymkey") or p.get("opaqueobj") or ("chave" in p and p["chave"] is None and not p.get("tokengroup")):
                # formato antigo do export (permissão sem chave ou sobre asymkey/opaqueobj): não gerenciada
                n_skip[kind] = n_skip.get(kind, 0) + 1
                continue
            if not p.get("chave") and not p.get("tokengroup"):
                raise ConfigError("%s para %s: informe 'chave' (ou 'tokengroup' para resolver a chave)" % (kind, p.get(subj)))
            nome = "%s@%s" % (p[subj], p.get("chave") or p.get("tokengroup"))
            D.add(kind, nome, {"nome": nome, subj: p[subj], "chave": p.get("chave"), "tokengroup": p.get("tokengroup"),
                               "tokenize": _bool(p.get("tokenize", False), "tokenize"),
                               "detokenize": _bool(p.get("detokenize", False), "detokenize")})
    for kind in sorted(n_skip):
        D.warnings.append("recursos.%s: %d permissão(ões) sem chave ou sobre asymkey/opaqueobj não são "
                          "gerenciadas e foram ignoradas" % (kind, n_skip[kind]))


def load_config(path, accept_suggestions=False):
    cfg = load_yaml(path)
    unknown = set(cfg) - TOP_KEYS
    if unknown:
        raise ConfigError("%s: chaves desconhecidas no topo: %s" % (path, sorted(unknown)))
    if cfg.get("versao", 1) != 1:
        raise ConfigError("%s: versao %r não suportada (esperado 1)" % (path, cfg.get("versao")))
    D = Desired()
    D.accept_suggestions = accept_suggestions
    conv = cfg.get("convencao") or {}
    if conv.get("sistemas"):
        D.convencao["sistemas"] = list(conv["sistemas"])
    if conv.get("datatypes"):
        D.convencao["datatypes"] = list(conv["datatypes"])
    api = cfg.get("api") or {}
    D.api["refs"] = dict(api.get("refs") or {})
    D.api["detail_trailing_slash"] = _bool(api.get("detail_trailing_slash", False), "api.detail_trailing_slash")
    for f, m in D.api["refs"].items():
        if m not in ("name", "id"):
            raise ConfigError("api.refs.%s deve ser 'name' ou 'id' (veio %r)" % (f, m))
    email_dom = (cfg.get("usuarios_padrao") or {}).get("email_dominio")
    expand_authoring(cfg, D)
    if cfg.get("recursos"):
        load_recursos(cfg["recursos"], D, email_dom)
    return D


# ----------------------------------------------------------------------------- modo legado (docs/)

def load_docs(docs_dir, D=None, key_map=None, email_domain=None, include_legacy=False,
              accept_suggestions=False):
    """Converte templates.yaml + usuarios-e-mascaras.yaml (+ checagens cruzadas) para Desired."""
    D = D or Desired()
    D.accept_suggestions = accept_suggestions
    key_map = key_map or {}
    tpath = os.path.join(docs_dir, "templates.yaml")
    upath = os.path.join(docs_dir, "usuarios-e-mascaras.yaml")
    t_raw = load_yaml(tpath)
    u_raw = load_yaml(upath)
    tg_of = {}
    for t in t_raw.get("templates") or []:
        nome = t.get("name")
        if str(t.get("uso", "")).upper().startswith("NAO_USAR") and not include_legacy:
            D.warnings.append("template legado '%s' ignorado (uso: %s); --include-legacy para incluir" % (nome, t.get("uso")))
            continue
        raw = {("nome" if k == "name" else k): v for k, v in t.items()}
        tpl = norm_template(raw, D, "templates.yaml/%s" % nome)
        D.add("templates", tpl["nome"], tpl)
        tg_of[tpl["nome"]] = tpl["tokengroup"]
        if tpl["tokengroup"] not in D.items["tokengroups"]:
            D.add("tokengroups", tpl["tokengroup"],
                  {"nome": tpl["tokengroup"], "chave": key_map.get(tpl["tokengroup"]), "bloqueios": []})
    for cat, lst in (u_raw.get("usuarios") or {}).items():
        for u in lst or []:
            nome = u["usuario"]
            meta = parse_user_name(nome, D.convencao["sistemas"], D.convencao["datatypes"])
            if not meta["conforme"]:
                D.warnings.append("usuário '%s' (docs) fora do padrão <sistema>_<datatype>[_<esquema>]: %s" % (
                    nome, "; ".join(meta["problemas"])))
            mname = None
            m = norm_mask(u.get("mascara"), "usuarios-e-mascaras.yaml/%s" % nome, D) if u.get("mascara") else None
            if m is not None:
                mname = nome[5:] if nome.startswith("ctvl_") else nome
                _add_mask(D, mname, m)
            mail = "%s@%s" % (nome, email_domain) if email_domain else None
            bl = [] if mail else ["e-mail é obrigatório na API e não foi declarado (use --email-domain)"]
            pr = "env:%s" % env_var_for(nome)
            D.add("usuarios", nome, {"nome": nome, "email": mail, "ativo": True, "grupos": [], "mascara": mname,
                                     "password_ref": pr,
                                     "convencao_nome": {k: meta[k] for k in ("sistema", "datatype", "esquema")},
                                     "bloqueios": bl})
            tk, dt = _perm_flags(u.get("permissoes"), "usuario %s" % nome)
            groups = sorted({tg_of[t] for t in (u.get("aplica_se_a_templates") or []) if t in tg_of})
            for t in u.get("aplica_se_a_templates") or []:
                if t not in tg_of:
                    D.warnings.append("usuário '%s' aplica-se ao template '%s', que não foi carregado" % (nome, t))
            for g in groups:
                chave = key_map.get(g)
                pn = "%s@%s" % (nome, chave or g)
                D.add("permissoes_usuarios", pn, {"nome": pn, "usuario": nome, "chave": chave, "tokengroup": g,
                                                  "tokenize": tk, "detokenize": dt})
    # checagem cruzada com perfis-keycloak.yaml, se existir
    ppath = os.path.join(docs_dir, "perfis-keycloak.yaml")
    if os.path.exists(ppath):
        perf = load_yaml(ppath)
        for pn, pd in (perf.get("perfis") or {}).items():
            for dtp, uname in ((pd or {}).get("usuarios_vault") or {}).items():
                if uname not in D.items["usuarios"]:
                    D.warnings.append("perfis-keycloak.yaml: perfil '%s' referencia usuário '%s' não declarado em usuarios-e-mascaras.yaml" % (pn, uname))
    return D
