"""Servidor falso MINIMO da API de dados do CT-VL (stdlib), so para autoteste offline dos cenarios.

Simula (nao e o cofre real): FPE deterministico sobre digitos preservando keepleft/keepright e o tamanho,
mascara por usuario, erro de negocio com HTTP 200, lista vazia => 1 item de erro, lote > 5000 => objeto,
HTTP 401 em HTML para credencial errada e falha intermitente de key store configuravel.
Os motivos de permissao negada sao PALPITE (o texto real do cofre e desconhecido)."""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LIMITE = 5000
MIN_MEIO = 6   # digitos "do meio" minimos (simula allowsmallinput=false); valor arbitrario do falso
GRUPOS = {"SES": {"SINDRAS_CPF": (3, 0), "SINDRAS_CNS": (0, 0)}}  # tokengroup existente; CPF: 3 primeiros em claro; CNS: nenhum
USUARIOS = {   # usuario -> (canPost, canGet, mascara (esq, dir)|None)
    "sindras_svc_tokenize": (True, False, None),
    "sindras_total": (False, True, None),
    "sindras_cpf_3_left_2_right": (False, True, (3, 2)),
    "sindras_cpf_0_left_2_right": (False, True, (0, 2)),
    "sindras_cns_3_left": (False, True, (3, 0)),
    "sindras_cns_0_left_0_right": (False, True, (0, 0)),
}
TRANSITORIO = "The requested key name was not found on the key store"
CHAVES_TOKENIZE = {"tokengroup", "tokentemplate", "data"}
CHAVES_DETOKENIZE = {"tokengroup", "token", "tokentemplate"}


def senha_de(usuario: str) -> str:
    """Senha do falso: derivada do nome, nao e segredo de ninguem."""
    return "offline-" + usuario


def _k(chave: str, i: int, ctx: str) -> int:
    return hmac.new(chave.encode(), f"{i}|{ctx}".encode(), hashlib.sha256).digest()[0] % 10


def cifrar(digitos: str, esq: int, dir_: int, chave: str, decifrar: bool = False) -> str:
    """Soma digito a digito (mod 10) de um deslocamento que depende do prefixo ja em claro: bijecao reversivel."""
    n = len(digitos)
    cabeca, cauda, meio = digitos[:esq], digitos[n - dir_:] if dir_ else "", digitos[esq:n - dir_]
    saida, claro = [], ""
    for i, d in enumerate(meio):
        k = _k(chave, i, cabeca + "|" + cauda + "|" + claro)
        if decifrar:
            c = str((int(d) - k) % 10)
            claro += c
        else:
            c = str((int(d) + k) % 10)
            claro += d
        saida.append(c)
    return cabeca + "".join(saida) + cauda


def _mascara(d: str, esq: int, dir_: int) -> str:
    n = len(d)
    if esq + dir_ >= n:
        return d
    return d[:esq] + "*" * (n - esq - dir_) + (d[n - dir_:] if dir_ else "")


def _erro(motivo: str) -> dict:
    return {"status": "error", "reason": f"{motivo} (X-Real-IP '10.0.0.7')"}


class _Estado:
    def __init__(self, falha_a_cada, desabilitados):
        self.falha_a_cada, self.desabilitados = falha_a_cada, set(desabilitados)
        self.chamadas = 0
        self.lock = threading.Lock()


def _item(estado: _Estado, usuario: str, op: str, it) -> dict:
    if not isinstance(it, dict):
        return _erro("Could not parse JSON input")
    permitidas = CHAVES_TOKENIZE if op == "tokenize" else CHAVES_DETOKENIZE
    if set(it) - permitidas:
        return _erro("Unknown JSON keyword encountered. Valid keywords for the " + op + " request are " + ", ".join(sorted(permitidas)))
    grupo = it.get("tokengroup")
    if grupo is None:
        return _erro("tokengroup not specified in JSON request.")
    if grupo not in GRUPOS:
        return _erro("The token group specified was not found in the database.")
    tpl = it.get("tokentemplate")
    if tpl not in GRUPOS[grupo]:
        return _erro("The requested combination of tokentemplate and tokengroup was not found in the tokentemplate table.")
    pode_post, pode_get, mascara = USUARIOS[usuario]
    if (op == "tokenize" and not pode_post) or (op == "detokenize" and (not pode_get or usuario in estado.desabilitados)):
        return _erro("User does not have permission to perform this operation")
    esq, dir_ = GRUPOS[grupo][tpl]
    valor = it.get("data" if op == "tokenize" else "token")
    if not isinstance(valor, str) or not valor.isdigit():
        return _erro("The input contains characters outside of the charset All digits")
    if len(valor) - esq - dir_ < MIN_MEIO:
        return _erro(f"After accounting for keepleft ({esq}) and keepright ({dir_}), not enough input characters are left to successfully {op} the input.")
    chave = f"{grupo}|{tpl}"
    if op == "tokenize":
        return {"status": "Succeed", "token": cifrar(valor, esq, dir_, chave)}
    claro = cifrar(valor, esq, dir_, chave, decifrar=True)
    return {"status": "Succeed", "data": _mascara(claro, *mascara) if mascara else claro}


def _tratar(estado: _Estado, usuario: str, op: str, corpo):
    """Devolve o JSON de resposta (HTTP 200 sempre; erro de negocio vai no item)."""
    if isinstance(corpo, list) and len(corpo) == 0:
        return [_erro("Empty request")]
    if isinstance(corpo, list) and len(corpo) > LIMITE:
        return {"status": "error", "reason": "Could not parse JSON input, perhaps it is too long."}
    with estado.lock:
        estado.chamadas += 1
        transitorio = estado.falha_a_cada and estado.chamadas % estado.falha_a_cada == 0
    itens = corpo if isinstance(corpo, list) else [corpo]
    if transitorio:
        res = [_erro(TRANSITORIO) for _ in itens]
    else:
        res = [_item(estado, usuario, op, i) for i in itens]
    return res if isinstance(corpo, list) else res[0]


class Servidor:
    def __init__(self, httpd: ThreadingHTTPServer, estado: _Estado):
        self._httpd, self.estado = httpd, estado
        self.url = f"http://127.0.0.1:{httpd.server_address[1]}"
        self._t = threading.Thread(target=httpd.serve_forever, daemon=True)
        self._t.start()

    def parar(self):
        self._httpd.shutdown()
        self._httpd.server_close()


def iniciar(falha_a_cada: int = 0, desabilitados=(), porta: int = 0) -> Servidor:
    """Sobe o falso numa porta livre (porta=0). falha_a_cada=N: toda N-esima chamada devolve a falha de key store."""
    estado = _Estado(falha_a_cada, desabilitados)

    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):  # silencioso
            pass

        def _responder(self, status, corpo, tipo="application/json"):
            dados = (corpo if isinstance(corpo, str) else json.dumps(corpo)).encode()
            self.send_response(status)
            self.send_header("Content-Type", tipo)
            self.send_header("Content-Length", str(len(dados)))
            self.end_headers()
            self.wfile.write(dados)

        def do_POST(self):
            tam = int(self.headers.get("Content-Length", 0))
            bruto = self.rfile.read(tam)
            usuario = None
            try:
                u, _, p = base64.b64decode(self.headers.get("Authorization", "Basic ")[6:]).decode().partition(":")
                if u in USUARIOS and hmac.compare_digest(p, senha_de(u)):
                    usuario = u
            except Exception:  # noqa: BLE001
                pass
            if usuario is None:
                return self._responder(401, "<html><body>401 Authorization Required</body></html>", "text/html")
            op = self.path.rstrip("/").rsplit("/", 1)[-1]
            if op not in ("tokenize", "detokenize"):
                return self._responder(404, "<html>404</html>", "text/html")
            try:
                corpo = json.loads(bruto)
            except ValueError:
                return self._responder(200, {"status": "error", "reason": "Could not parse JSON input"})
            self._responder(200, _tratar(estado, usuario, op, corpo))

    httpd = ThreadingHTTPServer(("127.0.0.1", porta), H)
    return Servidor(httpd, estado)
