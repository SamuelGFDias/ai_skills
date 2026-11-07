"""Cliente HTTP da API admin do CT-VL (urllib, sem dependências).

Token: lido de um arquivo (CTVL_TOKEN_FILE), nunca de argv. Nada aqui imprime token ou senha.
Sem redirecionamento automático: um 3xx vira erro (POST->GET silencioso mascararia falhas).
"""
import base64
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from .mask import mask_text


class CtvlError(Exception):
    code = 1


class AuthExpired(CtvlError):
    code = 77


class HttpFailure(CtvlError):
    def __init__(self, status, method, path, body):
        self.status = status
        self.body = body
        snippet = body if isinstance(body, str) else json.dumps(body, ensure_ascii=False)
        snippet = mask_text(snippet)[:400].replace("\n", " ")
        super().__init__("HTTP %s em %s %s: %s" % (status, method, path, snippet))


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def _ssl_context(ca, insecure):
    if insecure:
        sys.stderr.write("[ctvl] AVISO: verificação TLS desativada para este ambiente (opção explícita).\n")
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return ctx
    if ca:
        return ssl.create_default_context(cafile=ca)
    return ssl.create_default_context()


def _parse(raw):
    if not raw:
        return None
    try:
        return json.loads(raw.decode("utf-8"))
    except Exception:
        return raw.decode("utf-8", "replace")


class Client:
    """Cliente HTTP genérico. base = scheme://host + base_path."""

    def __init__(self, scheme, host, base_path, token_file=None, ca=None, insecure=False,
                 timeout=30, basic=None):
        self.base = "%s://%s%s" % (scheme, host, base_path.rstrip("/"))
        self.token_file = token_file
        self.timeout = timeout
        self.basic = basic  # (user, password) para a API de dados; nunca impresso
        self.opener = urllib.request.build_opener(
            _NoRedirect, urllib.request.HTTPSHandler(context=_ssl_context(ca, insecure)))
        self.read_only = False

    def _token(self):
        with open(self.token_file, "r", encoding="utf-8") as f:
            return f.read().strip()

    def request(self, method, path, body=None, query=None):
        if self.read_only and method != "GET":
            raise CtvlError("cliente somente leitura: %s %s bloqueado" % (method, path))
        url = self.base + path
        if query:
            url += ("&" if "?" in url else "?") + urllib.parse.urlencode(query)
        headers = {"Accept": "application/json", "User-Agent": "ctvl-api-skill"}
        if self.token_file:
            headers["Authorization"] = "Bearer " + self._token()
        elif self.basic:
            cred = base64.b64encode(("%s:%s" % self.basic).encode("utf-8")).decode("ascii")
            headers["Authorization"] = "Basic " + cred
        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with self.opener.open(req, timeout=self.timeout) as r:
                status, raw = r.status, r.read()
        except urllib.error.HTTPError as e:
            status, raw = e.code, e.read()
        except urllib.error.URLError as e:
            raise CtvlError("falha de conexão: %s" % mask_text(str(e.reason)))
        except OSError as e:
            raise CtvlError("falha de rede: %s" % mask_text(str(e)))
        parsed = _parse(raw)
        if status == 401 and self.token_file:
            raise AuthExpired("token rejeitado (401): expirado ou revogado")
        return status, parsed

    def get_all(self, path, query=None):
        """GET com paginação limit/offset; devolve a lista completa de resultados."""
        out, offset = [], 0
        for _ in range(500):
            q = dict(query or {})
            q.update({"limit": 200, "offset": offset})
            st, data = self.request("GET", path, query=q)
            if not 200 <= st < 300:
                raise HttpFailure(st, "GET", path, data)
            if isinstance(data, list):
                return data
            if not isinstance(data, dict) or "results" not in data:
                raise CtvlError("formato inesperado de listagem em %s" % path)
            res = data["results"]
            out.extend(res)
            if not res or not data.get("next"):
                break
            offset += len(res)
        return out


class FixtureClient:
    """Lê respostas de GET de arquivos <dir>/<path com / trocado por __>.json. Não escreve."""

    def __init__(self, directory):
        self.dir = directory
        self.read_only = True

    def _file(self, path):
        return os.path.join(self.dir, path.strip("/").replace("/", "__") + ".json")

    def get_all(self, path, query=None):
        f = self._file(path)
        if not os.path.exists(f):
            return []
        with open(f, encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict) and "results" in data:
            return data["results"]
        return data

    def request(self, method, path, body=None, query=None):
        if method != "GET":
            raise CtvlError("modo offline (--state-dir) não permite %s" % method)
        return 200, self.get_all(path)


class EmptyClient(FixtureClient):
    def __init__(self):
        super().__init__("")

    def get_all(self, path, query=None):
        return []


def client_from_env():
    """Monta o Client a partir das variáveis CTVL_CONN_* definidas por lib-ctvl.sh."""
    e = os.environ
    host = e.get("CTVL_CONN_HOST")
    if not host:
        raise CtvlError("conexão não configurada: execute pelos scripts (ctvl.sh <comando> <alias> ...), "
                        "que carregam as credenciais do ambiente")
    return Client(
        e.get("CTVL_CONN_SCHEME", "https"), host, e.get("CTVL_CONN_BASE", "/api"),
        token_file=e.get("CTVL_TOKEN_FILE") or None,
        ca=e.get("CTVL_CONN_CA") or None, insecure=e.get("CTVL_CONN_INSECURE") == "1")


def jwt_ttl(path):
    """Segundos restantes do JWT em path (claim exp). Sem exp, assume 240 s desde a gravação."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            tok = f.read().strip()
        payload = tok.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        exp = json.loads(base64.urlsafe_b64decode(payload.encode("ascii"))).get("exp")
        if exp is not None:
            return int(exp - time.time())
    except Exception:
        pass
    try:
        return int(240 - (time.time() - os.path.getmtime(path)))
    except OSError:
        return 0


def login(client, username, password, token_file):
    """POST /api-token-auth/ e grava o JWT (modo 600). Não imprime nada sensível."""
    st, data = client.request("POST", "/api-token-auth/", body={"username": username, "password": password})
    if not 200 <= st < 300:
        raise HttpFailure(st, "POST", "/api-token-auth/", data if st != 400 else "credenciais recusadas")
    tok = data.get("token") if isinstance(data, dict) else None
    if not tok:
        campos = ", ".join(sorted(data)) if isinstance(data, dict) else type(data).__name__
        raise CtvlError("resposta do login sem o campo 'token' (formato A CONFIRMAR). "
                        "Campos recebidos: %s" % campos)
    d = os.path.dirname(token_file)
    os.makedirs(d, mode=0o700, exist_ok=True)
    fd = os.open(token_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(tok)
    os.chmod(token_file, 0o600)
