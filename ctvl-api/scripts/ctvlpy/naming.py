"""Convenção de nomes: <sistema>_<datatype>[_<esquema>].

Usuário  : sindras_cns, settorj_cns, sindras_cpf_3_left_2_right
Serviço  : <sistema>_svc_<esquema>  (datatype reservado "svc"), ex.: sindras_svc_tokenize
Máscara  : [<sistema>_]<datatype>_<esquema>, ex.: cns_3_left (padrão) ou settorj_cns_3_left
"""
import re

DEFAULT_SISTEMAS = ["sindras", "biae", "settorj"]
DEFAULT_DATATYPES = ["cpf", "cns"]
RESERVED_SVC = "svc"

_TOKEN = re.compile(r"^[a-z0-9]+$")
_FULL = re.compile(r"^[a-z0-9]+(?:_[a-z0-9]+)*$")


def _result(nome, sistema=None, datatype=None, esquema=None, problemas=None):
    problemas = problemas or []
    return {
        "nome": nome, "sistema": sistema, "datatype": datatype, "esquema": esquema,
        "conforme": not problemas, "problemas": problemas,
    }


def parse_user_name(nome, sistemas=None, datatypes=None):
    """Extrai sistema, datatype e esquema de um nome de usuário e valida a convenção.

    Nunca ignora: um nome fora do padrão volta com conforme=False e a lista de problemas.
    """
    sistemas = sistemas or DEFAULT_SISTEMAS
    datatypes = datatypes or DEFAULT_DATATYPES
    if not isinstance(nome, str) or not nome:
        return _result(nome, problemas=["nome vazio ou não textual"])
    if not _FULL.match(nome):
        return _result(nome, problemas=["fora de [a-z0-9_] em minúsculas, sem '_' no início/fim nem '__'"])
    parts = nome.split("_")
    if len(parts) < 2:
        return _result(nome, problemas=["faltam partes: esperado <sistema>_<datatype>[_<esquema>]"])
    sistema, datatype = parts[0], parts[1]
    esquema = "_".join(parts[2:]) or None
    problemas = []
    if sistema not in sistemas:
        problemas.append("sistema '%s' não está na convenção (%s)" % (sistema, ", ".join(sistemas)))
    if datatype not in datatypes and datatype != RESERVED_SVC:
        problemas.append("datatype '%s' não está na convenção (%s, reservado: %s)" % (
            datatype, ", ".join(datatypes), RESERVED_SVC))
    if datatype == RESERVED_SVC and not esquema:
        problemas.append("usuário de serviço exige esquema (ex.: %s_svc_tokenize)" % sistema)
    return _result(nome, sistema, datatype, esquema, problemas)


def parse_mask_name(nome, sistemas=None, datatypes=None):
    """Máscara: [<sistema>_]<datatype>_<esquema>. Esquema é obrigatório."""
    sistemas = sistemas or DEFAULT_SISTEMAS
    datatypes = datatypes or DEFAULT_DATATYPES
    if not isinstance(nome, str) or not _FULL.match(nome or ""):
        return _result(nome, problemas=["fora de [a-z0-9_] em minúsculas"])
    parts = nome.split("_")
    sistema = None
    if parts[0] in sistemas:
        sistema = parts[0]
        parts = parts[1:]
    if len(parts) < 2:
        return _result(nome, sistema, problemas=["esperado [<sistema>_]<datatype>_<esquema>"])
    datatype, esquema = parts[0], "_".join(parts[1:])
    problemas = []
    if datatype not in datatypes:
        problemas.append("datatype '%s' não está na convenção (%s)" % (datatype, ", ".join(datatypes)))
    return _result(nome, sistema, datatype, esquema, problemas)


def build_user_name(sistema, datatype, esquema=None):
    return "_".join(p for p in (sistema, datatype, esquema) if p)


def env_var_for(nome):
    """CTVL_<NOME_EM_MAIÚSCULAS>_PASSWORD (padrão de referência de senha por env)."""
    return "CTVL_%s_PASSWORD" % re.sub(r"[^A-Za-z0-9]", "_", nome).upper()


_PASSWORD_VAR = re.compile(r"^CTVL_[A-Z0-9_]+_PASSWORD$")


def password_var_problem(var):
    """None se `var` pode ser lida como senha de usuário de dados; senão, o motivo da recusa.

    Só vale CTVL_<ALGO>_PASSWORD. A senha do admin (CTVL_ADMIN_PASSWORD[_<AMB>]) e as variáveis
    de login (CTVL_LOGIN_*) nunca podem ser lidas por password_ref: ela iria para o corpo de um
    POST /users/ ou para a API de dados.
    """
    if not isinstance(var, str) or not _PASSWORD_VAR.match(var):
        return "variável de senha '%s' inválida: use só o padrão CTVL_<NOME>_PASSWORD" % (var,)
    if var == "CTVL_ADMIN_PASSWORD" or var.startswith("CTVL_ADMIN_PASSWORD_") or var.startswith("CTVL_LOGIN_"):
        return "variável '%s' é de credencial ADMIN/login e não pode ser usada como senha de usuário" % var
    return None
