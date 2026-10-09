#!/usr/bin/env python3
"""Servidor FALSO do CT-VL, só para testes offline da skill (loopback). Segue o swagger.

 - API admin em /api (JWT fabricado), coleções em memória, paginação limit/offset.
 - `mask` de usuário: o swagger diz readOnly, mas o CT-VL real aceita `PUT /users/{id}` com `mask` = NOME da
   máscara (medido em DEV, 2026-10-08): 200 e "Mask successfully updated.". O fake imita:
   * usuário LOCAL (padrão): o PUT exige username e email (400 DRF "This field is required." se faltarem); campo
     omitido NÃO é alterado (comportamento DRF/JSON: groups, is_staff... ficam como estão);
   * usuário LDAP (seed `"ldap": true`): aceita o corpo só com `{"mask": nome}`;
   * máscara inexistente = 400; a releitura devolve sempre o NOME (nunca o id, mesmo com --ref-mode id).
   Seeds: `"mask_put_noop": true` faz o PUT responder 200 sem gravar (falha fechada); `"put_mutate": {"campo": valor}`
   faz o PUT gravar também esse campo extra (simula o servidor alterando algo além da máscara);
   `"put_empties_groups": true` simula um servidor que ESVAZIA `groups` quando o corpo não os traz (PUT completo);
   por usuário:
   `"groups": [nomes]` (criados no seed), `"is_staff"`, `"is_superuser"`, `"ldap"`; `"hide_user_fields": [campos]`
   faz o GET de usuário omitir esses campos (o PUT sem eles dá 400).
   O rastro dos PUTs de máscara (usuário, nome, corpo) sai em /__test/stats (`mask_puts`, `mask_put_bodies`).
 - --ref-mode name|id define como referências (tenant, key, groups...) são guardadas/devolvidas.
 - API de dados em /vts/rest/v2.0/{tokenize,detokenize} com Basic; erro de negócio = HTTP 200.
Credenciais admin vêm do ambiente do processo (FAKE_ADMIN_USER / FAKE_ADMIN_PASSWORD).
"""
import argparse
import base64
import json
import os
import re
import secrets
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

COLL = {
    "keys": dict(idf="idkey", name="name", req=["name"], refs={}),
    "charsets": dict(idf="idtokencharset", name="name", req=["name"], refs={}),
    "groups": dict(idf="id", name="name", req=["name"], refs={}),
    "masks": dict(idf="idmask", name="name", req=["name", "showleft", "showright", "maskchar"], refs={}),
    "users": dict(idf="id", name="username", req=["username", "email"], refs={"groups": ("groups", True)}),
    "tokengroups": dict(idf="idtenant", name="name", req=["name", "key"], refs={"key": ("keys", False)}),
    "tokentemplates": dict(idf="idtokentemplate", name="name", req=["name", "tenant", "format", "charset"],
                           refs={"tenant": ("tokengroups", False), "format": ("formats", False),
                                 "charset": ("charsets", False)}),
    "permissions/token/users": dict(idf="id", name=None, req=["user"], refs={"key": ("keys", False)}),
    "permissions/token/groups": dict(idf="id", name=None, req=["group"],
                                     refs={"key": ("keys", False), "group": ("groups", False)}),
}
WRITABLE = {
    "keys": ["name", "seedkey"], "charsets": ["name", "alphabet", "predefined", "range"], "groups": ["name"],
    "masks": ["name", "showleft", "showright", "maskchar"],
    "users": ["username", "email", "password", "is_active", "is_staff", "is_superuser", "groups"],
    "tokengroups": ["name", "key"],
    "tokentemplates": ["name", "tenant", "format", "charset", "keepleft", "keepright", "irreversible",
                       "copyruntdata", "allowsmallinput", "prefix", "startyear", "endyear",
                       "daterecordcount", "datetablenum"],
    "permissions/token/users": ["user", "key", "asymkey", "opaqueobj", "canPost", "canGet"],
    "permissions/token/groups": ["group", "key", "asymkey", "opaqueobj", "canPost", "canGet"],
}


class Store:
    def __init__(self, ref_mode, seed):
        self.ref_mode = ref_mode
        self.lock = threading.Lock()
        self.data = {k: [] for k in COLL}
        self.seq = {k: 0 for k in COLL}
        self.formats = [{"idtokenformat": 1, "name": "FPE"}, {"idtokenformat": 2, "name": "Random"}]
        self.tokens = {}
        self.passwords = {}
        self.user_mask = {}
        self.data_calls = 0
        self.nonce = secrets.token_hex(8)  # tokens de servidores diferentes nunca coincidem
        self.logins = 0
        self.bad_bearer = 0  # requisições com Bearer que este servidor não emitiu
        self.flaky = seed.get("flaky_first_data_calls", 0) if seed else 0
        self.mask_put_noop = bool(seed.get("mask_put_noop")) if seed else False
        self.mask_puts = []  # (username, máscara) de cada PUT de máscara aceito (rastro para os testes)
        self.mask_put_bodies = []  # [username, corpo] de cada PUT de máscara recebido (aceito ou não)
        self.put_mutate = dict(seed.get("put_mutate") or {}) if seed else {}
        self.hide_user_fields = list(seed.get("hide_user_fields") or []) if seed else []  # campos que o GET omite
        self.put_empties_groups = bool(seed.get("put_empties_groups")) if seed else False
        self.ldap = set()
        for c in (("Numeric", "0-9", True), ("All printable ASCII", "20-7E", True)):
            self.insert("charsets", {"name": c[0], "alphabet": c[1], "predefined": c[2], "range": True})
        for u in seed.get("users", []) if seed else []:
            for g in u.get("groups", []):
                if not self.find("groups", g):
                    self.insert("groups", {"name": g})
            self.insert("users", {"username": u["username"], "email": u["username"] + "@example.invalid",
                                  "is_active": True, "is_staff": bool(u.get("is_staff")),
                                  "is_superuser": bool(u.get("is_superuser")), "groups": list(u.get("groups", []))})
            if u.get("ldap"):
                self.ldap.add(u["username"])
            self.passwords[u["username"]] = u["password"]
            if u.get("mask"):
                self.user_mask[u["username"]] = u["mask"]

    def find(self, kind, name):
        nf = COLL[kind]["name"]
        for o in self.data[kind]:
            if o.get(nf) == name:
                return o

    def ref_out(self, target, name):
        if self.ref_mode == "name" or target == "formats":
            return name
        o = self.find(target, name)
        return o[COLL[target]["idf"]]

    def ref_in(self, target, value):
        """value (como veio no corpo) -> nome canônico, ou None se inválido."""
        if target == "formats":
            return value if value in [f["name"] for f in self.formats] else None
        if self.ref_mode == "name":
            return value if self.find(target, value) else None
        for o in self.data[target]:
            if o[COLL[target]["idf"]] == value:
                return o[COLL[target]["name"]]
        return None

    def insert(self, kind, body):
        self.seq[kind] += 1
        obj = {COLL[kind]["idf"]: self.seq[kind]}
        obj.update(body)
        self.data[kind].append(obj)
        return obj

    def present(self, kind, o):
        """Representação devolvida pela API (refs convertidas; hash de senha incluído de propósito)."""
        r = dict(o)
        for f, (target, many) in COLL[kind]["refs"].items():
            if f in r and r[f] not in (None, ""):
                r[f] = [self.ref_out(target, n) for n in r[f]] if many else self.ref_out(target, r[f])
        if kind == "users":
            r["password"] = "pbkdf2_sha256$600000$fakesalt$fakehashfakehash"
            r["is_superuser"] = bool(o.get("is_superuser"))
            r["is_staff"] = bool(o.get("is_staff"))
            r["ldap_user"] = o["username"] in self.ldap
            m = self.user_mask.get(o["username"])
            r["mask"] = m if m else None  # o CT-VL real devolve o NOME da máscara (medido em DEV)
            for f in self.hide_user_fields:
                r.pop(f, None)
        return r


def mk_handler(store, admin_user, admin_pw):
    class H(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *a):
            pass

        def _send(self, code, obj, raw=None):
            body = raw if raw is not None else json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _body(self):
            n = int(self.headers.get("Content-Length") or 0)
            if not n:
                return None
            try:
                return json.loads(self.rfile.read(n).decode())
            except ValueError:
                return "INVALID"

        def _auth_ok(self):
            h = self.headers.get("Authorization", "")
            return h.startswith("Bearer ") and h[7:] in store.tokens

        def do_GET(self): self.route("GET")
        def do_POST(self): self.route("POST")
        def do_PUT(self): self.route("PUT")
        def do_DELETE(self): self.route("DELETE")
        def do_PATCH(self): self.route("PATCH")

        def route(self, method):
            u = urlparse(self.path)
            path, q = u.path, parse_qs(u.query)
            body = self._body() if method in ("POST", "PUT", "PATCH") else None
            with store.lock:
                if path.startswith("/vts/rest/v2.0/"):
                    return self.data_api(method, path.rsplit("/", 1)[1], body)
                if path == "/__test/revoke" and method == "POST":
                    store.tokens.clear()
                    return self._send(200, {"ok": True})
                if path == "/__test/stats" and method == "GET":
                    return self._send(200, {"logins": store.logins, "bad_bearer": store.bad_bearer,
                                            "mask_puts": store.mask_puts,
                                            "mask_put_bodies": store.mask_put_bodies})
                if not path.startswith("/api/"):
                    return self._send(404, {"detail": "not found"})
                p = path[len("/api"):]
                if p == "/api-token-auth/" and method == "POST":
                    if not isinstance(body, dict) or body.get("username") != admin_user or body.get("password") != admin_pw:
                        return self._send(400, {"non_field_errors": ["Unable to log in with provided credentials."]})
                    hdr = base64.urlsafe_b64encode(b'{"alg":"HS256","typ":"JWT"}').decode().rstrip("=")
                    pl = base64.urlsafe_b64encode(json.dumps({"exp": int(time.time()) + 300, "n": len(store.tokens), "r": store.nonce}).encode()).decode().rstrip("=")
                    tok = "%s.%s.fakesignature%d" % (hdr, pl, len(store.tokens))
                    store.tokens[tok] = True
                    store.logins += 1
                    return self._send(201, {"token": tok})
                if not self._auth_ok():
                    if self.headers.get("Authorization", "").startswith("Bearer "):
                        store.bad_bearer += 1
                    return self._send(401, {"detail": "Authentication credentials were not provided."})
                if p.rstrip("/") == "/formats":
                    return self.listing(method, store.formats, q)
                m = re.match(r"^/(.+?)/?$", p)
                key = m.group(1)
                kind, oid = key, None
                if key not in COLL:
                    kind, _, tail = key.rpartition("/")
                    if kind in COLL and tail.isdigit():
                        oid = int(tail)
                    else:
                        return self._send(404, {"detail": "not found"})
                if oid is None:
                    return self.collection(kind, method, body, q)
                return self.detail(kind, oid, method, body)

        def listing(self, method, rows, q):
            if method != "GET":
                return self._send(405, {"detail": "method not allowed"})
            limit = int(q.get("limit", ["100"])[0])
            off = int(q.get("offset", ["0"])[0])
            page = rows[off:off + limit]
            nxt = "http://x/?offset=%d" % (off + limit) if off + limit < len(rows) else None
            return self._send(200, {"count": len(rows), "next": nxt, "previous": None, "results": page})

        def validate(self, kind, body):
            """Devolve (corpo canônico, erros). Erros no formato do DRF: {campo: [mensagens]}."""
            if not isinstance(body, dict):
                return None, {"detail": "invalid body"}
            miss = [f for f in COLL[kind]["req"] if f not in body or body[f] in (None, "")]
            if miss:
                return None, {f: ["This field is required."] for f in miss}
            canon = {f: body[f] for f in WRITABLE[kind] if f in body}
            for f, (target, many) in COLL[kind]["refs"].items():
                if f in canon and canon[f] not in (None, ""):
                    vals = canon[f] if many else [canon[f]]
                    names = [store.ref_in(target, v) for v in vals]
                    if any(n is None for n in names):
                        return None, {f: ["Invalid reference (formato/valor): %r" % (canon[f],)]}
                    canon[f] = names if many else names[0]
            if kind == "permissions/token/users" and not store.find("users", canon["user"]):
                return None, {"user": ["unknown user"]}
            return canon, None

        def collection(self, kind, method, body, q):
            if method == "GET":
                return self.listing(method, [store.present(kind, o) for o in store.data[kind]], q)
            if method != "POST":
                return self._send(405, {"detail": "method not allowed"})
            canon, errors = self.validate(kind, body)
            if errors:
                return self._send(400, errors)
            nf = COLL[kind]["name"]
            if nf and store.find(kind, canon[nf]):
                return self._send(400, {nf: ["already exists"]})
            if kind == "users":
                store.passwords[canon["username"]] = canon.pop("password", None)
                canon.setdefault("is_active", True)
                canon.setdefault("groups", [])
            obj = store.insert(kind, canon)
            return self._send(201, store.present(kind, obj))

        def detail(self, kind, oid, method, body):
            idf = COLL[kind]["idf"]
            obj = next((o for o in store.data[kind] if o[idf] == oid), None)
            if obj is None:
                return self._send(404, {"detail": "Not found."})
            if method == "GET":
                return self._send(200, store.present(kind, obj))
            if method == "DELETE":
                store.data[kind].remove(obj)
                return self._send(204, None, raw=b"")
            if kind == "users" and method == "PUT" and isinstance(body, dict) and "mask" in body:
                store.mask_put_bodies.append([obj["username"], body])
                if obj["username"] in store.ldap:
                    if set(body) != {"mask"}:
                        return self._send(400, {"detail": "usuário LDAP: o fake só aceita {\"mask\"}"})
                    canon = {}
                else:
                    canon, errors = self.validate(kind, body)  # usuário local: username e email obrigatórios
                    if errors:
                        return self._send(400, errors)
                name = body["mask"]
                if not isinstance(name, str) or not store.find("masks", name):
                    return self._send(400, {"mask": ["Invalid mask: %r" % (name,)]})
                if not store.mask_put_noop:
                    canon.pop("password", None)
                    if store.put_empties_groups and obj["username"] not in store.ldap:
                        canon.setdefault("groups", [])  # servidor simulado de PUT completo: sem `groups`, esvazia
                    obj.update(canon)
                    obj.update(store.put_mutate)
                    store.user_mask[obj["username"]] = name
                    store.mask_puts.append((obj["username"], name))
                return self._send(200, "Mask successfully updated.")
            if method in ("PUT", "PATCH"):
                canon, errors = self.validate(kind, body)
                if errors:
                    return self._send(400, errors)
                canon.pop("password", None)
                obj.update(canon)
                return self._send(200, store.present(kind, obj))
            return self._send(405, {"detail": "method not allowed"})

        def data_api(self, method, op, body):
            if method != "POST":
                return self._send(405, {"detail": "nginx: method not allowed"}, raw=b"<html>405</html>")
            h = self.headers.get("Authorization", "")
            try:
                user, pw = base64.b64decode(h[6:]).decode().split(":", 1)
            except Exception:
                return self._send(401, None, raw=b"<html>401</html>")
            if store.passwords.get(user) != pw:
                return self._send(401, None, raw=b"<html>401</html>")
            store.data_calls += 1
            if store.data_calls <= store.flaky:
                return self._send(200, {"status": "error", "reason": "The requested key name was not found on the key store."})
            items = body if isinstance(body, list) else [body]
            out = []
            for it in items:
                tg, tpl = it.get("tokengroup"), it.get("tokentemplate")
                t = store.find("tokentemplates", tpl)
                if not store.find("tokengroups", tg):
                    out.append({"status": "error", "reason": "The token group specified was not found in the database."})
                    continue
                if not t or store.ref_in("tokengroups", t["tenant"]) is None:
                    out.append({"status": "error", "reason": "The requested combination of tokentemplate and tokengroup was not found in the tokentemplate table."})
                    continue
                kl, kr = t.get("keepleft", 0), t.get("keepright", 0)
                if op == "tokenize":
                    out.append({"status": "Succeed", "token": self.shift(it["data"], kl, kr, 3)})
                else:
                    plain = self.shift(it["token"], kl, kr, -3)
                    mname = store.user_mask.get(user)
                    mk = store.find("masks", mname) if mname else None
                    if mk:
                        n, L, R = len(plain), mk["showleft"], mk["showright"]
                        if L + R < n:
                            plain = plain[:L] + mk["maskchar"] * (n - L - R) + (plain[n - R:] if R else "")
                    out.append({"status": "Succeed", "data": plain})
            return self._send(200, out if isinstance(body, list) else out[0])

        @staticmethod
        def shift(s, kl, kr, d):
            mid = s[kl:len(s) - kr if kr else len(s)]
            mid = "".join(str((int(c) + d) % 10) if c.isdigit() else c for c in mid)
            return s[:kl] + mid + (s[len(s) - kr:] if kr else "")
    return H


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref-mode", choices=["name", "id"], default="name")
    ap.add_argument("--port-file", required=True)
    ap.add_argument("--seed")
    a = ap.parse_args()
    seed = json.load(open(a.seed)) if a.seed else {}
    store = Store(a.ref_mode, seed)
    user, pw = os.environ["FAKE_ADMIN_USER"], os.environ["FAKE_ADMIN_PASSWORD"]
    srv = ThreadingHTTPServer(("127.0.0.1", 0), mk_handler(store, user, pw))
    with open(a.port_file, "w") as f:
        f.write(str(srv.server_address[1]))
    srv.serve_forever()


if __name__ == "__main__":
    sys.exit(main())
