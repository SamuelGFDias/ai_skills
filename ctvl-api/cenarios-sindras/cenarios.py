#!/usr/bin/env python3
"""Runner dos cenarios de validacao das regras da feature 004 contra o cofre CT-VL DEV (ou contra o falso offline).

Uso: cenarios.py [--cenario C1|1|C1,C3|todos] [--amostra 50] [--lote 1000] [--so-leitura] [--offline] [--verbose]
Dado pessoal: sempre sintetico (gerado em lib.py). Saida: uma linha por cenario; detalhes SEM dado/token em out/."""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib  # noqa: E402
from lib import ErroCofre, TEMPLATE  # noqa: E402

def _pasta_out() -> Path:
    """SINDRAS_ROOT/scripts/ctvl-experiments/out se existir; senao ./out no cwd (nunca dentro da skill)."""
    for r in lib.raizes_sindras():
        d = r / "scripts" / "ctvl-experiments" / "out"
        if d.parent.is_dir():
            return d
    destino = Path.cwd() / "out"
    kit = Path(__file__).resolve().parent
    if kit == destino.resolve().parent or kit in destino.resolve().parents:
        return kit / "out"                       # dentro do kit, onde o .gitignore cobre out/
    return destino


OUT = _pasta_out()
PASS, FAIL, SKIP, MEDICAO = "PASS", "FAIL", "SKIP", "MEDIÇÃO"


@dataclass
class Resultado:
    status: str
    motivo: str
    detalhes: dict = field(default_factory=dict)
    linhas: list[str] = field(default_factory=list)   # sub-linhas curtas (usadas na MEDIÇÃO)


class Ctx:
    def __init__(self, args, abrir_cofre):
        self.amostra, self.lote, self.so_leitura = args.amostra, args.lote, args.so_leitura
        self._abrir, self._cofres = abrir_cofre, {}

    def cofre(self, usuario: str) -> lib.Cofre:
        if usuario not in self._cofres:
            self._cofres[usuario] = self._abrir(usuario)
        return self._cofres[usuario]

    @property
    def chamadas(self) -> int:
        return sum(c.stats.chamadas for c in self._cofres.values())


# ---- helpers ---------------------------------------------------------------------------------------------
def tokenizar(ctx: Ctx, tipo: str, valores, lote=None) -> list[str]:
    """Pipeline do app: normaliza + valida DV (sem cofre se invalido) + tokeniza com o usuario de servico."""
    prep = lib.preparar(valores, tipo)
    itens = lib.tokenize(prep, TEMPLATE[tipo], ctx.cofre("sindras_svc_tokenize"), lote=lote or ctx.lote)
    return _valores(itens)


def _valores(itens) -> list[str]:
    falhas = Counter(i.categoria for i in itens if not i.ok)
    if falhas:
        raise ErroCofre("itens", f"{sum(falhas.values())} item(ns) com falha {dict(falhas)}")
    return [i.valor for i in itens]


def formatar(valor: str, tipo: str) -> str:
    return (f"{valor[:3]}.{valor[3:6]}.{valor[6:9]}-{valor[9:]}" if tipo == "cpf"
            else f"{valor[:3]} {valor[3:7]} {valor[7:11]} {valor[11:]}")


def forma(s: str) -> str:
    """Forma sem dado: D=digito, *=mascara, x=outro."""
    return "".join("D" if c.isdigit() else "*" if c == "*" else "x" for c in s)


def veredito(falhas: list[str], ok_msg: str, detalhes: dict, status_ok: str = PASS) -> Resultado:
    if falhas:
        return Resultado(FAIL, f"{len(falhas)} falha(s): {falhas[0]}", {**detalhes, "falhas": falhas})
    return Resultado(status_ok, ok_msg, detalhes)


def media_lcp(tokens: list[str]) -> float:
    def lcp(a, b):
        n = 0
        while n < min(len(a), len(b)) and a[n] == b[n]:
            n += 1
        return n
    pares = [(a, b) for i, a in enumerate(tokens) for b in tokens[i + 1:]]
    return sum(lcp(a, b) for a, b in pares) / max(1, len(pares))


# ---- C1 normalizacao e determinismo (FR-001/002/004) -----------------------------------------------------
def c1(ctx: Ctx) -> Resultado:
    falhas, det = [], {}
    antes = ctx.chamadas
    for tipo in ("cpf", "cns"):
        v = lib.gerar(tipo, 1, 1)[0]
        ruim = v[:-1] + str((int(v[-1]) + 1) % 10)
        for entrada in (ruim, v[:-1], "a" * len(v)):
            try:
                tokenizar(ctx, tipo, [v, entrada])
                falhas.append(f"{tipo}: entrada invalida aceita")
            except lib.ValorInvalido:
                pass
    det["chamadas_com_dv_invalido"] = ctx.chamadas - antes
    if det["chamadas_com_dv_invalido"] != 0:
        falhas.append(f"DV invalido chamou o cofre ({det['chamadas_com_dv_invalido']} chamadas)")
    if ctx.so_leitura:
        return veredito(falhas, "(parcial, --so-leitura) DV inválido recusado com 0 chamadas ao cofre", det)
    for tipo in ("cpf", "cns"):
        vals = lib.gerar(tipo, ctx.amostra, 100)
        t_pont, t_plano = tokenizar(ctx, tipo, [formatar(vals[0], tipo), vals[0]])
        if t_pont != t_plano:
            falhas.append(f"{tipo}: com e sem pontuacao geram tokens diferentes")
        toks = tokenizar(ctx, tipo, vals)
        if not all(t.isdigit() and len(t) == len(v) for t, v in zip(toks, vals)):
            falhas.append(f"{tipo}: token nao e so digitos do mesmo tamanho da entrada")
        if toks != tokenizar(ctx, tipo, vals):
            falhas.append(f"{tipo}: mesma entrada gerou tokens diferentes")
        if len(set(toks)) != len(vals):
            falhas.append(f"{tipo}: colisao entre entradas distintas")
        det[f"{tipo}_amostra"] = len(vals)
    return veredito(falhas, f"normalização, determinismo e unicidade (N={ctx.amostra} CPF e CNS); DV inválido: 0 chamadas", det)


# ---- C2 round trip e perfis (FR-005/008) -----------------------------------------------------------------
def _negado(e: Exception | None = None, itens=None) -> bool:
    if e is not None:
        return isinstance(e, ErroCofre) and e.categoria in ("permissao", "autenticacao")
    return bool(itens) and all(not i.ok and i.categoria == "permissao" for i in itens)


def c2(ctx: Ctx) -> Resultado:
    if ctx.so_leitura:
        return Resultado(SKIP, "--so-leitura: round trip exige tokenize")
    falhas, pulados, det = [], [], {"perfis": {}}
    ok_perfis, incidencia = 0, "indeterminada"
    for tipo in ("cpf", "cns"):
        orig = lib.gerar(tipo, ctx.amostra, 200)
        toks = tokenizar(ctx, tipo, orig)
        total = _valores(lib.detokenize(toks, TEMPLATE[tipo], ctx.cofre("sindras_total"), lote=ctx.lote))
        if total != orig:
            falhas.append(f"{tipo}: sindras_total nao devolve o original ({sum(a != b for a, b in zip(total, orig))} divergentes)")
        det["perfis"][f"total_{tipo}"] = total == orig
        for usuario, (_, dt, (esq, dir_)) in lib.MASCARADOS.items():
            if dt != tipo:
                continue
            esperado = [lib.aplicar_mascara(o, esq, dir_) for o in orig]
            try:
                itens = lib.detokenize(toks, TEMPLATE[tipo], ctx.cofre(usuario), lote=ctx.lote)
            except ErroCofre as e:
                if _negado(e):
                    pulados.append(usuario)
                    det["perfis"][usuario] = f"SKIP ({e.categoria})"
                    continue
                raise
            if _negado(itens=itens):
                pulados.append(usuario)
                det["perfis"][usuario] = "SKIP (permissao)"
                continue
            obtido = _valores(itens)
            div = [i for i, (a, b) in enumerate(zip(obtido, esperado)) if a != b]
            det["perfis"][usuario] = "ok" if not div else f"{len(div)} divergentes; forma obtida={forma(obtido[div[0]])} esperada={forma(esperado[div[0]])}"
            if div:
                falhas.append(f"{usuario}: mascara diverge em {len(div)}/{len(orig)} (forma {forma(obtido[div[0]])} vs {forma(esperado[div[0]])})")
            else:
                ok_perfis += 1
                incidencia = "sobre os dígitos"
    # onde incide a mascara: o cofre mascara o que foi tokenizado; sondar com valor pontuado
    try:
        v = lib.gerar_cpf(300)
        itens = lib.tokenize([formatar(v, "cpf")], TEMPLATE["cpf"], ctx.cofre("sindras_svc_tokenize"))
        det["pontuacao_aceita_no_tokenize"] = itens[0].ok
        if itens[0].ok:
            det["token_pontuado_so_digitos"] = itens[0].valor.isdigit()
            det["token_pontuado_tamanho"] = len(itens[0].valor)
    except ErroCofre as e:
        det["pontuacao_aceita_no_tokenize"] = f"erro {e.categoria}"
    det["incidencia_da_mascara"] = incidencia
    if falhas:
        return veredito(falhas, "", det)
    if pulados:
        return Resultado(SKIP, f"round trip total ok; {len(pulados)} perfil(is) sem permissão de detokenizar ({', '.join(pulados)}): rode `fluxo-dev.sh habilitar <u> --yes`", det)
    return Resultado(PASS, f"round trip + 4 perfis (CPF 3+2, CPF 0+2, CNS 3, CNS 0+0; máscara {incidencia}, '*'); pontuação no tokenize: {det['pontuacao_aceita_no_tokenize']}", det)


# ---- C3 lote e erros (FR-010/011) ------------------------------------------------------------------------
def c3(ctx: Ctx) -> Resultado:
    falhas, det = [], {"lotes": {}}
    total = ctx.cofre("sindras_total")
    if not ctx.so_leitura:
        for n, ini in ((1, 10_000), (1000, 20_000), (5000, 30_000)):
            orig = lib.gerar_cpfs(n, ini)
            t0 = time.perf_counter()
            toks = _valores(lib.tokenize(orig, TEMPLATE["cpf"], ctx.cofre("sindras_svc_tokenize"), lote=n))
            volta = _valores(lib.detokenize(toks, TEMPLATE["cpf"], total, lote=n))
            det["lotes"][str(n)] = {"ok": volta == orig, "segundos": round(time.perf_counter() - t0, 2)}
            if volta != orig:
                falhas.append(f"lote de {n}: round trip diverge")
    # acima do limite: devolve objeto; o cliente detecta sem quebrar (usa tokens ficticios so de digitos, leitura)
    corpo = [{"tokengroup": lib.TOKENGROUP, "tokentemplate": TEMPLATE["cpf"], "token": "0" * 11}] * 5156
    for _ in range(3):
        status, data = total.enviar(lib.URL_DETOKENIZE, corpo)
        if not (isinstance(data, list) and data and all(isinstance(i, dict) and "key store" in str(i.get("reason", "")) for i in data)):
            break
    try:
        lib.validar_resposta_lote(data, len(corpo), "data")
        falhas.append("5156 itens nao foram recusados (limite diferente do medido)")
        det["acima_do_limite"] = "aceito"
    except lib.RespostaInvalida as e:
        det["acima_do_limite"] = f"detectado ({e.categoria}), HTTP {status}"
    # lista vazia nunca e enviada
    antes = ctx.chamadas
    for fn in (lambda: lib.tokenize([], TEMPLATE["cpf"], total), lambda: lib.detokenize([], TEMPLATE["cpf"], total)):
        try:
            fn()
            falhas.append("lista vazia nao foi recusada")
        except lib.ListaVazia:
            pass
    det["chamadas_com_lista_vazia"] = ctx.chamadas - antes
    if ctx.chamadas != antes:
        falhas.append("lista vazia chegou ao cofre")
    # item com token invalido: falha so do item
    if ctx.so_leitura:
        orig, toks = None, [lib.gerar_cpf(401), lib.gerar_cpf(402)]
    else:
        orig = lib.gerar_cpfs(2, 40_000)
        toks = _valores(lib.tokenize(orig, TEMPLATE["cpf"], ctx.cofre("sindras_svc_tokenize")))
    itens = lib.detokenize([toks[0], "x", toks[1]], TEMPLATE["cpf"], total)
    det["item_invalido"] = {"ok_por_item": [i.ok for i in itens], "categoria": itens[1].categoria}
    if len(itens) != 3 or itens[1].ok or itens[1].valor is not None or not (itens[0].ok and itens[2].ok):
        falhas.append("token invalido derrubou o lote ou foi exibido como dado")
    elif orig is not None and [itens[0].valor, itens[2].valor] != orig:
        falhas.append("itens validos do lote com erro nao voltaram corretos")
    sufixo = " (parcial, --so-leitura)" if ctx.so_leitura else ""
    return veredito(falhas, f"lotes 1/1000/5000 ok; 5156 {det['acima_do_limite']}; lista vazia: 0 chamadas; token inválido isola o item{sufixo}"
                    if not ctx.so_leitura else f"5156 {det['acima_do_limite']}; lista vazia: 0 chamadas; token inválido isola o item{sufixo}", det)


# ---- C4 resiliencia (FR-015/016) -------------------------------------------------------------------------
def c4(ctx: Ctx) -> Resultado:
    falhas, det = [], {}
    n = max(20, ctx.amostra)
    total = ctx.cofre("sindras_total")
    tok = [lib.gerar_cpf(501)]   # so digitos; detokenize e leitura
    base = total.stats.chamadas_com_transitorio
    sem_retry = [lib.detokenize(tok, TEMPLATE["cpf"], total, tentativas=1)[0] for _ in range(n)]
    transit = total.stats.chamadas_com_transitorio - base
    com_retry = [lib.detokenize(tok, TEMPLATE["cpf"], total, tentativas=3)[0] for _ in range(n)]
    definitivas = sum(not i.ok for i in com_retry)
    det.update(chamadas=n, falha_intermitente_sem_retry=transit, falhas_definitivas_com_retry=definitivas)
    if definitivas:
        falhas.append(f"retry nao absorveu {definitivas}/{n} falhas")
    if any((not i.ok) and i.valor is not None for i in sem_retry + com_retry):
        falhas.append("item com falha carregou valor")
    # falha definitiva nunca vira dado nem valor padrao (transporte em processo)
    transit_item = {"status": "error", "reason": "The requested key name was not found on the key store"}
    sempre = lib.Cofre(lambda p, b: (200, [transit_item] * len(b)), usuario="stub", dormir=lambda s: None)
    r = lib.detokenize(tok, TEMPLATE["cpf"], sempre, tentativas=3)[0]
    if r.ok or r.valor is not None or sempre.stats.chamadas != 3:
        falhas.append("falha definitiva virou dado/valor padrao ou retry ilimitado")
    mudo = lib.Cofre(lambda p, b: (None, "Timeout"), usuario="stub", dormir=lambda s: None)
    try:
        lib.detokenize(tok, TEMPLATE["cpf"], mudo, tentativas=2)
        falhas.append("tempo esgotado engolido")
    except ErroCofre as e:
        det["timeout"] = e.categoria
    taxa = f"{transit}/{n} sem retry" if transit else f"0/{n} (retry não exercitado)"
    return veredito(falhas, f"falha intermitente {taxa}; com retry {definitivas}/{n} falhas; falha definitiva não vira dado", det)


# ---- C5 isolamento (FR-023) ------------------------------------------------------------------------------
def c5(ctx: Ctx) -> Resultado:
    falhas, det = [], {}

    def nao_vaza(itens, orig, rotulo):
        vazou = sum(i.ok and i.valor == o for i, o in zip(itens, orig))
        det[rotulo] = {"falhas_do_cofre": sum(not i.ok for i in itens), "devolveu_original": vazou}
        if vazou:
            falhas.append(f"{rotulo}: devolveu o original em {vazou} item(ns)")

    svc, total = ctx.cofre("sindras_svc_tokenize"), ctx.cofre("sindras_total")
    if ctx.so_leitura:
        orig, toks = None, lib.gerar_cpfs(5, 600)       # tokens ficticios (so digitos): leitura
    else:
        orig = lib.gerar_cpfs(10, 50_000)
        toks = _valores(lib.tokenize(orig, TEMPLATE["cpf"], svc))
        nao_vaza(lib.detokenize(toks, TEMPLATE["cns"], total), orig, "template_trocado")
        nao_vaza(lib.detokenize(toks, TEMPLATE["cpf"], total, tokengroup="GRUPO_INEXISTENTE"), orig, "grupo_trocado")
        try:   # usuario so de detokenize nao tokeniza
            it = lib.tokenize(orig[:1], TEMPLATE["cpf"], total, tentativas=1)
            det["total_tokeniza"] = it[0].ok
            if it[0].ok:
                falhas.append("sindras_total conseguiu tokenizar")
        except ErroCofre as e:
            det["total_tokeniza"] = f"negado ({e.categoria})"
    try:   # servico de tokenize nao detokeniza (canGet=false)
        itens = lib.detokenize(toks, TEMPLATE["cpf"], svc)
        nao_vaza(itens, orig or [None] * len(itens), "svc_detokeniza")
        if orig is None and any(i.ok for i in itens):
            det["svc_detokeniza"]["aviso"] = "sucesso com token ficticio"
            falhas.append("sindras_svc_tokenize detokenizou (canGet deveria ser false)")
    except ErroCofre as e:
        det["svc_detokeniza"] = f"negado ({e.categoria})"
    sufixo = " (parcial, --so-leitura)" if ctx.so_leitura else ""
    return veredito(falhas, f"template/grupo trocado nunca devolvem o original; svc não detokeniza; total não tokeniza{sufixo}"
                    if not ctx.so_leitura else f"svc não detokeniza{sufixo}", det)


# ---- C6 medicoes abertas (A-03/A-04, P-04, small inputs, prefixo) ----------------------------------------
def c6(ctx: Ctx) -> Resultado:
    if ctx.so_leitura:
        return Resultado(SKIP, "--so-leitura: medições exigem tokenize")
    det, linhas = {}, []
    n = ctx.amostra
    # (a) digitos em claro
    for tipo, (e, d) in (("cpf", (3, 2)), ("cns", (3, 0))):
        orig = lib.gerar(tipo, n, 700)
        toks = tokenizar(ctx, tipo, orig)
        pre = sum(t[:e] == o[:e] for t, o in zip(toks, orig)) / n
        suf = sum(t[len(t) - d:] == o[len(o) - d:] for t, o in zip(toks, orig)) / n if d else None
        meio = [t[e] == o[e] for t, o in zip(toks, orig)]
        det[f"a_{tipo}"] = {"prefixo_em_claro": pre, "sufixo_em_claro": suf, "pos_seguinte_ao_prefixo_igual": sum(meio) / n}
        linhas.append(f"(a) {tipo}: {e} primeiros em claro em {pre:.0%}" + (f", {d} últimos em {suf:.0%}" if d else "")
                      + f"; dígito seguinte igual em {sum(meio) / n:.0%} (acaso ~10%)")
    # (b) comprimento minimo aceito
    for tipo in ("cpf", "cns"):
        aceitos = []
        for tam in range(1, 17):
            it = lib.tokenize([("1234567890" * 2)[:tam]], TEMPLATE[tipo], ctx.cofre("sindras_svc_tokenize"))[0]
            if it.ok:
                aceitos.append(tam)
        minimo = min(aceitos) if aceitos else None
        det[f"b_{tipo}"] = {"minimo_aceito": minimo, "aceitos": aceitos}
        linhas.append(f"(b) {tipo}: menor entrada aceita = {minimo} dígito(s) (testado 1..16; allowsmallinput=false)")
    # (c) fracao de tokens que parecem CPF/CNS validos
    m = max(n, 1000)
    for tipo, valido in (("cpf", lib.cpf_valido), ("cns", lib.cns_valido)):
        toks = tokenizar(ctx, tipo, lib.gerar(tipo, m, 5000), lote=1000)
        k = sum(valido(t) for t in toks)
        det[f"c_{tipo}"] = {"amostra": m, "tokens_com_dv_valido": k, "fracao": k / m}
        linhas.append(f"(c) {tipo}: {k}/{m} tokens ({k / m:.1%}) têm DV válido (aleatório esperado: CPF ~1%, CNS ~7-9%)")
    # (d) StartsWith: alem dos 3 digitos em claro, o prefixo do token acompanha o prefixo da entrada?
    import random
    base3 = lib.gerar_cpf(777)[:3]

    def com_prefixo(prefixo: str, n_: int, seed: int) -> list[str]:
        r, saida = random.Random(seed), []
        while len(saida) < n_:
            nove = prefixo + "".join(str(r.randint(0, 9)) for _ in range(9 - len(prefixo)))
            c = nove + lib._dv_cpf(nove)
            c += lib._dv_cpf(c)
            if len(set(nove)) > 1 and c not in saida:
                saida.append(c)
        return saida
    grupos = {"3 primeiros iguais": com_prefixo(base3, 60, 1), "6 primeiros iguais": com_prefixo(lib.gerar_cpf(778)[:6], 60, 2)}
    lcps = {k: media_lcp(tokenizar(ctx, "cpf", v)) for k, v in grupos.items()}
    det["d_cpf"] = {"lcp_medio_dos_tokens": lcps}
    linhas.append("(d) cpf: LCP médio dos tokens com " + " / ".join(f"{k}: {v:.2f}" for k, v in lcps.items())
                  + "; se só o 3 em claro conta, ambos ~3 (StartsWith vale até 3 dígitos)")
    return Resultado(MEDICAO, f"{len(linhas)} medições (A-03/A-04, P-04, entrada mínima, prefixo); ver out/", det, linhas)


CENARIOS = {"C1": (c1, "normalização e determinismo"), "C2": (c2, "round trip e perfis"), "C3": (c3, "lote e erros"),
            "C4": (c4, "resiliência"), "C5": (c5, "isolamento"), "C6": (c6, "medições abertas")}


# ---- execucao --------------------------------------------------------------------------------------------
def selecionar(txt: str) -> list[str]:
    if txt.lower() == "todos":
        return list(CENARIOS)
    ids = [("C" + p.strip().lstrip("cC")) for p in txt.split(",") if p.strip()]
    desconhecidos = [i for i in ids if i not in CENARIOS]
    if desconhecidos:
        raise SystemExit(f"cenário desconhecido: {', '.join(desconhecidos)} (use C1..C6 ou todos)")
    return ids


def abrir_offline(srv):
    import fake_dados

    def abrir(usuario):
        return lib.Cofre(lib.transporte_http(srv.url, usuario, fake_dados.senha_de(usuario)), usuario=usuario, espera=0.0)
    return abrir


def abrir_real():
    cfg = lib.carregar_config()
    senhas = lib.senhas_do_ambiente()

    def abrir(usuario):
        return lib.Cofre(lib.transporte_http(cfg["url"], usuario, senhas[usuario], cfg["verify"], cfg["timeout"]),
                         usuario=usuario, espera=1.0)
    return abrir


def principal(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--cenario", default="todos")
    ap.add_argument("--amostra", type=int, default=50)
    ap.add_argument("--lote", type=int, default=lib.LOTE_PADRAO)
    ap.add_argument("--so-leitura", action="store_true", help="pula escritas (tokenize); roda só o que lê/valida")
    ap.add_argument("--offline", action="store_true", help="usa o servidor falso local (autoteste do runner)")
    ap.add_argument("--offline-desabilitar", default="", help="(com --offline) usuarios sem canGet, separados por virgula")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args(argv)
    if args.amostra < 2:
        raise SystemExit("--amostra deve ser >= 2")
    if not 1 <= args.lote <= lib.MAX_LOTE:
        raise SystemExit(f"--lote deve estar em 1..{lib.MAX_LOTE}")
    ids = selecionar(args.cenario)

    srv = None
    try:
        if args.offline:
            import fake_dados
            srv = fake_dados.iniciar(falha_a_cada=7, desabilitados=[u for u in args.offline_desabilitar.split(",") if u])
            abrir = abrir_offline(srv)
        else:
            abrir = abrir_real()
    except ErroCofre as e:
        print(f"ERRO de configuração: {lib.mascarar_texto(e)}", file=sys.stderr)
        return 2
    modo = "offline" if args.offline else "dev"
    ctx = Ctx(args, abrir)
    destino = OUT / f"cenarios-{modo}"
    destino.mkdir(parents=True, exist_ok=True)
    print(f"CT-VL cenários [{modo}] amostra={args.amostra} lote={args.lote}{' so-leitura' if args.so_leitura else ''}")
    cont = Counter()
    try:
        for cid in ids:
            fn, nome = CENARIOS[cid]
            t0 = time.perf_counter()
            try:
                r = fn(ctx)
            except ErroCofre as e:
                r = Resultado(FAIL, lib.mascarar_texto(f"{nome}: {e}"))
            except Exception as e:  # noqa: BLE001
                r = Resultado(FAIL, f"{nome}: erro inesperado {type(e).__name__}")
            cont[r.status] += 1
            print(f"{cid}  {r.status:<8} {r.motivo}")
            for ln in r.linhas:
                print(f"      {ln}")
            if args.verbose and r.detalhes:
                print("      detalhes: " + lib.mascarar_texto(json.dumps(r.detalhes, ensure_ascii=False)))
            (destino / f"{cid}.json").write_text(json.dumps(
                {"status": r.status, "motivo": r.motivo, "segundos": round(time.perf_counter() - t0, 2),
                 "detalhes": r.detalhes, "medicoes": r.linhas}, ensure_ascii=False, indent=2), encoding="utf-8")
    finally:
        if srv:
            srv.parar()
    print(f"Totais: {cont[PASS]} PASS, {cont[FAIL]} FAIL, {cont[SKIP]} SKIP, {cont[MEDICAO]} MEDIÇÃO | "
          f"chamadas ao cofre: {ctx.chamadas} | detalhes: {destino}/")
    return 1 if cont[FAIL] else 0


if __name__ == "__main__":
    sys.exit(principal())
