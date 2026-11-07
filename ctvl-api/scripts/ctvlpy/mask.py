"""Mascaramento de segredos, tokens e IPs em qualquer saída da skill."""
import os
import re

_SENSITIVE_KEY = re.compile(
    r"(password|passwd|secret|hash|authorization|session_key|jwt|api[_-]?key|"
    r"access_token|refresh_token|credential)", re.I)
_EXACT_KEYS = {"token"}
_IP_KEYS = {"ip_address"}

_RE_JWT = re.compile(r"eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]*")
_RE_AUTH = re.compile(r"(?i)\b(bearer|basic|jwt)\s+[A-Za-z0-9._~+/=-]{8,}")
_RE_IPV4 = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
_RE_IPV6 = re.compile(
    r"\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b"
    r"|\b(?:[0-9a-fA-F]{1,4}:){1,6}:(?:[0-9a-fA-F]{1,4})?\b"
    r"|(?<![\w:])::1\b")


def mask_text(s):
    """Mascara JWT, cabeçalhos de autorização, IPs e o host configurado."""
    if not isinstance(s, str):
        return s
    host = os.environ.get("CTVL_HOST_MASK", "")
    if host:
        s = s.replace(host, "<host>")
    s = _RE_JWT.sub("<jwt>", s)
    s = _RE_AUTH.sub(lambda m: m.group(1) + " ***", s)
    s = _RE_IPV6.sub("<ip>", s)
    s = _RE_IPV4.sub("<ip>", s)
    return s


def is_sensitive_key(k):
    k = str(k)
    return k.lower() in _EXACT_KEYS or bool(_SENSITIVE_KEY.search(k))


def mask_obj(o):
    """Cópia de o com valores de chaves sensíveis trocados por *** e texto mascarado."""
    if isinstance(o, dict):
        out = {}
        for k, v in o.items():
            if is_sensitive_key(k):
                out[k] = "***"
            elif str(k).lower() in _IP_KEYS:
                out[k] = "<ip>"
            else:
                out[k] = mask_obj(v)
        return out
    if isinstance(o, list):
        return [mask_obj(v) for v in o]
    if isinstance(o, str):
        return mask_text(o)
    return o


def body_has_secret_key(o):
    """True se o corpo tem alguma chave de senha/segredo (para recusar --body inline)."""
    if isinstance(o, dict):
        return any(is_sensitive_key(k) or body_has_secret_key(v) for k, v in o.items())
    if isinstance(o, list):
        return any(body_has_secret_key(v) for v in o)
    return False
