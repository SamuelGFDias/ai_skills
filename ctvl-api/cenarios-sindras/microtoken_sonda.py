#!/usr/bin/env python3
"""Sonda do Microtoken (fachada HTTP do CT-VL) com dados sintéticos.

Lê MICROTOKEN_URL e MICROTOKEN_KEY_{SERVICO,TOTAL,PARCIAL,MINIMO} do ambiente
(`set -a; source ~/dev/microtoken-dev.env; set +a`). Chave vazia: pula as
verificações daquele perfil. Nunca imprime chave, token, CPF/CNS nem texto de
erro com dígitos: só status, formas, tamanhos e contagens.
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib  # noqa: E402

URL = os.environ.get("MICROTOKEN_URL", "").rstrip("/")
CHAVES = {p: os.environ.get(f"MICROTOKEN_KEY_{p.upper()}", "") for p in ("servico", "total", "parcial", "minimo")}


def chamar(caminho, corpo, chave, *, timeout=60.0):
    cab = {"Content-Type": "application/json"}
    if chave is not None:
        cab["X-API-Key"] = chave
    req = urllib.request.Request(URL + caminho, data=json.dumps(corpo).encode(), headers=cab, method="POST")
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            bruto, status, h = r.read(), r.status, r.headers
    except urllib.error.HTTPError as e:
        bruto, status, h = e.read(), e.code, e.headers
    except Exception as e:  # transporte
        return {"status": None, "erro_transporte": type(e).__name__, "ms": int((time.monotonic() - t0) * 1000)}
    try:
        js = json.loads(bruto)
    except ValueError:
        js = None
    return {"status": status, "json": js, "tam": len(bruto), "req_id_hdr": bool(h.get("X-Request-ID")),
            "ms": int((time.monotonic() - t0) * 1000)}


def forma(js):
    if isinstance(js, list):
        return f"lista[{len(js)}]" + (f" itens:{sorted({tuple(sorted(i)) if isinstance(i, dict) else type(i).__name__ for i in js}, key=str)[:3]}" if js else "")
    if isinstance(js, dict):
        return "objeto" + str(sorted(js))
    return type(js).__name__ if js is not None else "nao-json"


def sem_digitos(txt, n=90):
    return re.sub(r"\d", "#", str(txt))[:n]


def resumo(r):
    if r["status"] is None:
        return f"transporte:{r['erro_transporte']} {r['ms']}ms"
    js = r["json"]
    extra = ""
    if isinstance(js, dict) and "error" in js:
        extra = f" error='{sem_digitos(js['error'])}' req_id={'sim' if js.get('request_id') else 'nao'} up={js.get('upstream_status')}"
    return f"HTTP {r['status']} {forma(js)}{extra} X-Request-ID={'sim' if r['req_id_hdr'] else 'nao'} {r['ms']}ms"


def linha(rotulo, r):
    print(f"  {rotulo}: {resumo(r)}", flush=True)


def token_de(r):
    js = r.get("json")
    if isinstance(js, dict):
        return js.get("token")
    return None


def so_digitos(s):
    return isinstance(s, str) and s.isdigit()


def main():
    if not URL or not CHAVES["servico"]:
        print("MICROTOKEN_URL e MICROTOKEN_KEY_SERVICO são obrigatórios"); return 2
    print("perfis com chave:", [p for p, v in CHAVES.items() if v], "| sem chave:", [p for p, v in CHAVES.items() if not v])
    S, T = CHAVES["servico"], CHAVES["total"]
    cpfs = lib.gerar("cpf", 5, 9001)
    cnss = lib.gerar("cns", 5, 9001)
    cpf, cns = cpfs[0], cnss[0]

    print("\n[A] tokenize unitário (servico)")
    r = chamar("/tokenize/cpf", {"cpf": cpf}, S); linha("cpf", r)
    tk_cpf = token_de(r)
    if tk_cpf:
        print(f"    token: tam={len(tk_cpf)} (dado {len(cpf)}) so_digitos={so_digitos(tk_cpf)} 3_primeiros_iguais={tk_cpf[:3] == cpf[:3]} difere_do_dado={tk_cpf != cpf}")
    r = chamar("/tokenize/cns", {"cns": cns}, S); linha("cns", r)
    tk_cns = token_de(r)
    if tk_cns:
        print(f"    token: tam={len(tk_cns)} (dado {len(cns)}) so_digitos={so_digitos(tk_cns)} 3_primeiros_iguais={tk_cns[:3] == cns[:3]} difere_do_dado={tk_cns != cns}")

    print("\n[B] determinismo e normalização")
    r2 = chamar("/tokenize/cpf", {"cpf": cpf}, S); print("  repetido igual:", token_de(r2) == tk_cpf)
    fmt = f"{cpf[:3]}.{cpf[3:6]}.{cpf[6:9]}-{cpf[9:]}"
    r3 = chamar("/tokenize/cpf", {"cpf": fmt}, S); linha("com pontuação", r3); print("  pontuado == sem pontuação:", token_de(r3) == tk_cpf)

    print("\n[C] lote pequeno (servico) e ordem")
    r = chamar("/tokenize/cpf", [{"cpf": c} for c in cpfs], S); linha("lote 5", r)
    js = r.get("json")
    if isinstance(js, list) and len(js) == 5:
        print("    chaves por item:", sorted({tuple(sorted(i)) for i in js if isinstance(i, dict)}))
        print("    status por item:", sorted({str(i.get("status")) for i in js if isinstance(i, dict)}))
        print("    1º item == tokenize unitário:", js[0].get("token") == tk_cpf)
    r = chamar("/tokenize/cpf", [], S); linha("lista vazia", r)

    print("\n[D] entradas inválidas")
    curto8 = cpf[:8]
    linha("cpf 8 dígitos (unit)", chamar("/tokenize/cpf", {"cpf": curto8}, S))
    linha("cpf 9 dígitos (unit)", chamar("/tokenize/cpf", {"cpf": cpf[:9]}, S))
    linha("cns 5 dígitos (unit)", chamar("/tokenize/cns", {"cns": cns[:5]}, S))
    linha("cns 6 dígitos (unit)", chamar("/tokenize/cns", {"cns": cns[:6]}, S))
    linha("letras (unit)", chamar("/tokenize/cpf", {"cpf": "abcdefghijk"}, S))
    linha("vazio (unit)", chamar("/tokenize/cpf", {"cpf": ""}, S))
    linha("nulo (unit)", chamar("/tokenize/cpf", {"cpf": None}, S))
    linha("campo errado no corpo", chamar("/tokenize/cpf", {"cns": cpf}, S))
    r = chamar("/tokenize/cpf", [{"cpf": cpfs[1]}, {"cpf": curto8}, {"cpf": cpfs[2]}], S); linha("lote com 1 curto entre 2 válidos", r)
    js = r.get("json")
    if isinstance(js, list):
        print("    por item:", [(sorted(i), i.get("status")) if isinstance(i, dict) else type(i).__name__ for i in js])

    print("\n[E] limites do lote (servico, cpf)")
    for n in (1000, 5000, 5001, 5156, 10000):
        lote = [{"cpf": c} for c in lib.gerar("cpf", n, 20001)]
        linha(f"lote {n}", chamar("/tokenize/cpf", lote, S, timeout=180))

    print("\n[F] autenticação e datatype")
    linha("sem chave", chamar("/tokenize/cpf", {"cpf": cpf}, None))
    linha("chave inválida", chamar("/tokenize/cpf", {"cpf": cpf}, "mtk_invalida_sintetica"))
    linha("datatype inexistente", chamar("/tokenize/xyz", {"xyz": cpf}, S))
    linha("corpo não JSON-objeto (string)", chamar("/tokenize/cpf", "texto", S))

    print("\n[G] detokenize com cada perfil")
    for perfil in ("servico", "total", "parcial", "minimo"):
        k = CHAVES[perfil]
        if not k:
            print(f"  ({perfil}: sem chave, não medido)"); continue
        for tipo, tk, orig in (("cpf", tk_cpf, cpf), ("cns", tk_cns, cns)):
            if not tk:
                continue
            for clear in ("false", "true"):
                r = chamar(f"/detokenize/{tipo}?clear={clear}", {tipo: tk}, k)
                js = r.get("json"); d = js.get("data") if isinstance(js, dict) else None
                extra = ""
                if isinstance(d, str):
                    mascara = "".join("*" if ch == "*" else "d" for ch in d)
                    extra = f" tam={len(d)} igual_ao_original={d == orig} padrão={mascara}"
                print(f"  {perfil} {tipo} clear={clear}: {resumo(r)}{extra}")

    print("\n[H] detokenize em lote e item inválido (total)")
    if T and tk_cpf:
        r = chamar("/tokenize/cpf", [{"cpf": c} for c in cpfs[:3]], S)
        toks = [i.get("token") for i in (r.get("json") or []) if isinstance(i, dict)]
        r = chamar("/detokenize/cpf?clear=true", [{"cpf": t} for t in toks], T); linha("lote 3 tokens", r)
        js = r.get("json")
        if isinstance(js, list):
            print("    ordem preservada e igual ao original:", [i.get("data") for i in js if isinstance(i, dict)] == cpfs[:3])
        r = chamar("/detokenize/cpf?clear=true", [{"cpf": toks[0]}, {"cpf": "00000000000"}, {"cpf": toks[1]}], T); linha("lote com token inexistente no meio", r)
        js = r.get("json")
        if isinstance(js, list):
            print("    por item:", [(sorted(i), i.get("status")) if isinstance(i, dict) else type(i).__name__ for i in js])
        linha("token inexistente (unit)", chamar("/detokenize/cpf?clear=true", {"cpf": "00000000000"}, T))
        linha("lista vazia", chamar("/detokenize/cpf?clear=true", [], T))

    print("\n[I] repetição: 40 chamadas unitárias e 10 lotes de 100 (servico)")
    cont, ms = {}, []
    for c in lib.gerar("cpf", 40, 30001):
        r = chamar("/tokenize/cpf", {"cpf": c}, S); cont[str(r["status"])] = cont.get(str(r["status"]), 0) + 1; ms.append(r["ms"])
    print(f"  unitárias: status={cont} p50={sorted(ms)[len(ms)//2]}ms max={max(ms)}ms")
    cont, ms = {}, []
    for i in range(10):
        lote = [{"cpf": c} for c in lib.gerar("cpf", 100, 40001 + i * 100)]
        r = chamar("/tokenize/cpf", lote, S); cont[str(r["status"])] = cont.get(str(r["status"]), 0) + 1; ms.append(r["ms"])
    print(f"  lotes de 100: status={cont} p50={sorted(ms)[len(ms)//2]}ms max={max(ms)}ms")
    return 0


if __name__ == "__main__":
    sys.exit(main())
