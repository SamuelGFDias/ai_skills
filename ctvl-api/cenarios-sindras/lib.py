"""Funcoes puras e cliente minimo do cofre CT-VL para os cenarios de validacao da feature 004.

Regras: dado pessoal e SEMPRE sintetico (gerado aqui, FR-024); nada de CPF/CNS/token/senha/host em saida
(FR-021/022): mensagens de erro carregam so categorias e contagens. O transporte e injetavel (testes offline).
Autonomo: nao depende de nenhum modulo do projeto Sindras."""
from __future__ import annotations

import os
import random
import re
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Sequence

# ---- constantes do cofre (config-sindras-dev.yaml do Sindras) ---------------------------------
URL_TOKENIZE = "/vts/rest/v2.0/tokenize"
URL_DETOKENIZE = "/vts/rest/v2.0/detokenize"
TOKENGROUP = "SES"      # tokengroup existente no vault (chave CTS); os templates SINDRAS_* ficam sob ele
TEMPLATE = {"cpf": "SINDRAS_CPF", "cns": "SINDRAS_CNS"}
MAX_LOTE = 5000      # medido em RESULTADOS.md (Sonda 5): 5000 ok, 5156 falha
LOTE_PADRAO = 1000

# usuario do cofre -> (sufixo da variavel de senha, datatype|None, mascara (esq, dir)|None)
USUARIOS = {
    "sindras_svc_tokenize": ("SVC_TOKENIZE", None, None),
    "sindras_total": ("TOTAL", None, None),
    "sindras_cpf_3_left_2_right": ("CPF_3_LEFT_2_RIGHT", "cpf", (3, 2)),
    "sindras_cpf_0_left_2_right": ("CPF_0_LEFT_2_RIGHT", "cpf", (0, 2)),
    "sindras_cns_3_left": ("CNS_3_LEFT", "cns", (3, 0)),
    "sindras_cns_0_left_0_right": ("CNS_0_LEFT_0_RIGHT", "cns", (0, 0)),
}
MASCARADOS = {u: v for u, v in USUARIOS.items() if v[2] is not None}
MASK_CHAR = "*"


def nome_var_senha(usuario: str) -> str:
    return f"CTVL_SINDRAS_{USUARIOS[usuario][0]}_PASSWORD"


# ---- segredos e saida segura -----------------------------------------------------------------------------
_SEGREDOS: set[str] = set()


def registrar_segredo(valor: str) -> None:
    if valor and len(valor) >= 4:
        _SEGREDOS.add(valor)


def mascarar_texto(s) -> str:
    s = str(s)
    for sec in sorted(_SEGREDOS, key=len, reverse=True):
        s = s.replace(sec, "<MASK>")
    return re.sub(r"https?://[^\s'\"]+", "<URL>", s)


def sanitizar_motivo(txt) -> str:
    """Motivo cru do cofre -> versao segura para detalhes: sem IP, URL nem sequencias longas de digitos."""
    s = re.sub(r"\(X-Real-IP[^)]*\)", "", str(txt))
    s = re.sub(r"https?://\S+", "<URL>", s)
    s = re.sub(r"\b\d{1,3}(?:\.\d{1,3}){3}\b", "<IP>", s)
    s = re.sub(r"\d{6,}", "<N>", s)
    return mascarar_texto(s).strip()[:160]


_CATEGORIAS = (
    ("key store", "transitorio"),
    ("not enough input characters", "entrada"),
    ("combination of tokentemplate and tokengroup", "template"),
    ("token group specified was not found", "grupo"),
    ("unknown json keyword", "contrato"),
    ("could not parse json", "limite"),
    ("permission", "permissao"), ("not authorized", "permissao"), ("unauthorized", "permissao"),
    ("forbidden", "permissao"), ("denied", "permissao"), ("not allowed", "permissao"),
)


def classificar_motivo(txt) -> str:
    t = str(txt).lower()
    for trecho, cat in _CATEGORIAS:
        if trecho in t:
            return cat
    return "outro"


# ---- normalizacao, CPF e CNS sinteticos ------------------------------------------------------------------
def apenas_digitos(s) -> str:
    return re.sub(r"\D", "", str(s))


def _dv_cpf(base: str) -> str:
    n = len(base) + 1
    t = sum(int(d) * (n - i) for i, d in enumerate(base)) * 10 % 11
    return str(0 if t == 10 else t)


def cpf_valido(valor) -> bool:
    c = apenas_digitos(valor)
    if len(c) != 11 or len(set(c)) == 1 or not str(valor).strip():
        return False
    return c[9] == _dv_cpf(c[:9]) and c[10] == _dv_cpf(c[:10])


def _soma_cns(c: str) -> int:
    return sum(int(d) * (15 - i) for i, d in enumerate(c))


def cns_valido(valor) -> bool:
    c = apenas_digitos(valor)
    if len(c) != 15 or c[0] not in "12789" or not str(valor).strip():
        return False
    return _soma_cns(c) % 11 == 0


def gerar_cpf(seed: int) -> str:
    r = random.Random(7919 * seed + 13)
    while True:
        nove = "".join(str(r.randint(0, 9)) for _ in range(9))
        if len(set(nove)) > 1:
            d1 = _dv_cpf(nove)
            return nove + d1 + _dv_cpf(nove + d1)


def gerar_cpfs(n: int, inicio: int = 1) -> list[str]:
    saida, vistos, i = [], set(), inicio
    while len(saida) < n:
        c = gerar_cpf(i)
        i += 1
        if c not in vistos:
            vistos.add(c)
            saida.append(c)
    return saida


def _dv_pis(pis11: str) -> str:
    """CNS definitivo (iniciado em 1 ou 2): PIS + '000'/'001' + DV (algoritmo oficial)."""
    soma = sum(int(d) * (15 - i) for i, d in enumerate(pis11))
    dv = 11 - soma % 11
    dv = 0 if dv == 11 else dv
    if dv == 10:
        soma += 2
        dv = 11 - soma % 11
        dv = 0 if dv == 11 else dv
        return "001" + str(dv)
    return "000" + str(dv)


def gerar_cns(seed: int, tipo: str = "definitivo") -> str:
    r = random.Random(104729 * seed + 7)
    if tipo == "definitivo":
        pis = str(r.choice("12")) + "".join(str(r.randint(0, 9)) for _ in range(10))
        return pis + _dv_pis(pis)
    if tipo == "provisorio":   # iniciado em 7, 8 ou 9: soma ponderada multipla de 11
        while True:
            c14 = str(r.choice("789")) + "".join(str(r.randint(0, 9)) for _ in range(13))
            ultimo = (-sum(int(d) * (15 - i) for i, d in enumerate(c14))) % 11
            if ultimo <= 9:
                return c14 + str(ultimo)
    raise ValueError("tipo de CNS: 'definitivo' ou 'provisorio'")


def gerar_cnss(n: int, inicio: int = 1) -> list[str]:
    saida, vistos, i = [], set(), inicio
    while len(saida) < n:
        c = gerar_cns(i, "definitivo" if i % 2 else "provisorio")
        i += 1
        if c not in vistos:
            vistos.add(c)
            saida.append(c)
    return saida


def gerar(tipo: str, n: int, inicio: int = 1) -> list[str]:
    return {"cpf": gerar_cpfs, "cns": gerar_cnss}[tipo](n, inicio)


class ValorInvalido(ValueError):
    """CPF/CNS invalido (FR-001). A mensagem traz so o indice, nunca o valor."""


class ListaVazia(ValueError):
    """Lista vazia nunca e enviada ao cofre (ele devolve 1 item de erro)."""


def preparar(valores: Sequence[str], tipo: str) -> list[str]:
    """Normaliza para so digitos (FR-002) e valida DV (FR-001) ANTES de qualquer chamada ao cofre."""
    validar = {"cpf": cpf_valido, "cns": cns_valido}.get(tipo)
    if validar is None:
        raise ValueError("tipo: 'cpf' ou 'cns'")
    saida = []
    for i, v in enumerate(valores):
        if not validar(v):
            raise ValorInvalido(f"{tipo} invalido no item {i} (DV/formato)")
        saida.append(apenas_digitos(v))
    return saida


def aplicar_mascara(digitos: str, esq: int, dir_: int, ch: str = MASK_CHAR) -> str:
    n = len(digitos)
    if esq + dir_ >= n:
        return digitos
    return digitos[:esq] + ch * (n - esq - dir_) + (digitos[n - dir_:] if dir_ else "")


# ---- lotes e validacao de resposta (FR-010/011) ----------------------------------------------------------
def dividir_lotes(itens: Sequence, tamanho: int = LOTE_PADRAO) -> list[list]:
    if not 1 <= tamanho <= MAX_LOTE:
        raise ValueError(f"tamanho de lote deve estar em 1..{MAX_LOTE}")
    if len(itens) == 0:
        raise ListaVazia("lista vazia nao e enviada ao cofre")
    return [list(itens[i:i + tamanho]) for i in range(0, len(itens), tamanho)]


@dataclass(frozen=True)
class Item:
    ok: bool
    valor: str | None = None      # None sempre que ok=False (nunca token no lugar do dado)
    categoria: str = ""           # vazio se ok
    motivo: str = ""              # motivo sanitizado (sem IP/URL/digitos longos)


class ErroCofre(Exception):
    def __init__(self, categoria: str, detalhe: str = ""):
        super().__init__(f"cofre: {categoria}" + (f" ({detalhe})" if detalhe else ""))
        self.categoria = categoria


class RespostaInvalida(ErroCofre):
    """Forma/tamanho inesperado da resposta de um lote."""


def validar_resposta_lote(resp, n: int, campo: str) -> list[Item]:
    """Exige lista de n objetos; cada item so e ok com status == 'Succeed' e `campo` textual (FR-011)."""
    if isinstance(resp, dict):   # excesso de lote: objeto no lugar de lista
        cat = classificar_motivo(resp.get("reason", ""))
        raise RespostaInvalida(cat if cat != "outro" else "forma", f"objeto no lugar de lista; esperado {n} itens")
    if not isinstance(resp, list):
        raise RespostaInvalida("forma", f"corpo {type(resp).__name__}; esperado lista de {n}")
    if len(resp) != n:
        raise RespostaInvalida("forma", f"{len(resp)} itens; esperado {n}")
    itens = []
    for it in resp:
        if not isinstance(it, dict):
            raise RespostaInvalida("forma", "item que nao e objeto")
        if it.get("status") == "Succeed":
            v = it.get(campo)
            itens.append(Item(True, v) if isinstance(v, str) and v else Item(False, None, "forma", f"sem '{campo}'"))
        else:
            motivo = it.get("reason", "")
            itens.append(Item(False, None, classificar_motivo(motivo), sanitizar_motivo(motivo)))
    return itens


# ---- cofre (transporte injetavel) ------------------------------------------------------------------------
Transporte = Callable[[str, object], "tuple[int | None, object]"]


@dataclass
class Stats:
    chamadas: int = 0
    chamadas_com_transitorio: int = 0
    itens_transitorios: int = 0
    retries: int = 0


@dataclass
class Cofre:
    transporte: Transporte
    usuario: str = ""
    dormir: Callable[[float], None] = time.sleep
    espera: float = 1.0
    stats: Stats = field(default_factory=Stats)

    def enviar(self, path: str, body):
        self.stats.chamadas += 1
        return self.transporte(path, body)


def transporte_http(base_url: str, usuario: str, senha: str, verify=True, timeout: float = 60.0) -> Transporte:
    import httpx
    registrar_segredo(senha)
    registrar_segredo(base_url)
    registrar_segredo(base_url.split("://")[-1].split("/")[0])
    c = httpx.Client(base_url=base_url, auth=(usuario, senha), verify=verify, timeout=timeout,
                     headers={"Accept": "application/json"})

    def enviar(path, body):
        try:
            r = c.post(path, json=body)
        except Exception as e:  # noqa: BLE001
            return None, f"{type(e).__name__}"
        try:
            return r.status_code, r.json()
        except Exception:  # noqa: BLE001
            return r.status_code, "<corpo nao-JSON>"
    return enviar


def _executar(cofre: Cofre, path: str, corpos: list[dict], campo: str, tentativas: int) -> list[Item]:
    """Um lote com retry limitado so da falha intermitente de key store; reenvia apenas os itens afetados."""
    if tentativas < 1:
        raise ValueError("tentativas >= 1")
    itens: list[Item | None] = [None] * len(corpos)
    pend = list(range(len(corpos)))
    for tentativa in range(1, tentativas + 1):
        status, data = cofre.enviar(path, [corpos[i] for i in pend])
        if status is None or status >= 500:
            if tentativa == tentativas:
                raise ErroCofre("rede", f"HTTP {status}" if status else "sem resposta")
            cofre.stats.retries += 1
            cofre.dormir(cofre.espera)
            continue
        if status in (401, 403):
            raise ErroCofre("autenticacao" if status == 401 else "permissao", f"HTTP {status}")
        if status != 200:
            raise ErroCofre("http", f"HTTP {status}")
        novos = []
        resp = validar_resposta_lote(data, len(pend), campo)
        if any(i.categoria == "transitorio" for i in resp):
            cofre.stats.chamadas_com_transitorio += 1
        for idx, it in zip(pend, resp):
            itens[idx] = it
            if it.categoria == "transitorio":
                cofre.stats.itens_transitorios += 1
                novos.append(idx)
        pend = novos
        if not pend:
            break
        if tentativa < tentativas:
            cofre.stats.retries += 1
            cofre.dormir(cofre.espera)
    return itens  # type: ignore[return-value]


def _em_lotes(cofre, path, valores, montar, campo, lote, tentativas):
    saida: list[Item] = []
    for parte in dividir_lotes(valores, lote):
        saida.extend(_executar(cofre, path, [montar(v) for v in parte], campo, tentativas))
    return saida


def tokenize(valores: Sequence[str], template: str, cofre: Cofre, *, tokengroup: str = TOKENGROUP,
             lote: int = LOTE_PADRAO, tentativas: int = 3) -> list[Item]:
    return _em_lotes(cofre, URL_TOKENIZE, valores,
                     lambda v: {"tokengroup": tokengroup, "tokentemplate": template, "data": v}, "token", lote, tentativas)


def detokenize(tokens: Sequence[str], template: str, usuario: Cofre, *, tokengroup: str = TOKENGROUP,
               lote: int = LOTE_PADRAO, tentativas: int = 3) -> list[Item]:
    """`usuario` e o Cofre ligado as credenciais do usuario que detokeniza (o perfil vem da credencial, FR-008)."""
    return _em_lotes(usuario, URL_DETOKENIZE, tokens,
                     lambda t: {"tokengroup": tokengroup, "tokentemplate": template, "token": t}, "data", lote, tentativas)


# ---- configuracao a partir do ambiente (sem imprimir nada) -----------------------------------------------
def _ler_env_arquivo(p: Path) -> dict[str, str]:
    saida = {}
    for linha in p.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        k, v = linha.removeprefix("export ").split("=", 1)
        v = v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        saida[k.strip()] = v
    return saida


REL_ENV_DEV = Path("src/Sindras.Infra.CrossCutting/ConfigurationEnvironment/.env.Development")


def raizes_sindras() -> list[Path]:
    """Raizes candidatas do checkout do Sindras: SINDRAS_ROOT, cwd e `git rev-parse --show-toplevel` do cwd."""
    raizes: list[Path] = []
    if os.environ.get("SINDRAS_ROOT"):
        raizes.append(Path(os.environ["SINDRAS_ROOT"]).expanduser())
    raizes.append(Path.cwd())
    try:
        import subprocess
        r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=10)
        if r.returncode == 0 and r.stdout.strip():
            raizes.append(Path(r.stdout.strip()))
    except (OSError, subprocess.SubprocessError):
        pass
    return raizes


def _candidatos_env_dev() -> list[Path]:
    cands = []
    if os.environ.get("CTVL_ENV_FILE"):
        cands.append(Path(os.environ["CTVL_ENV_FILE"]))
    cands.extend(r / REL_ENV_DEV for r in raizes_sindras())
    return cands


def carregar_config() -> dict:
    """Host/CA/TLS/timeout: do ambiente ou do .env.Development (host e CA nao sao senhas). Senhas: so do ambiente."""
    base: dict[str, str] = {}
    for p in _candidatos_env_dev():
        if p.is_file():
            base = {k: v for k, v in _ler_env_arquivo(p).items() if k in
                    ("CTVL_HOST", "CTVL_CA_BUNDLE", "CTVL_TIMEOUT_SECONDS", "CTVL_INSECURE_TLS")}
            base["_dir"] = str(p.parent)
            break
    cfg = {k: os.environ.get(k, base.get(k, "")) for k in
           ("CTVL_HOST", "CTVL_CA_BUNDLE", "CTVL_TIMEOUT_SECONDS", "CTVL_INSECURE_TLS")}
    host = cfg["CTVL_HOST"].rstrip("/")
    if not host:
        raise ErroCofre("config", "CTVL_HOST ausente (ambiente, CTVL_ENV_FILE ou .env.Development do Sindras via SINDRAS_ROOT/cwd)")
    url = host if "://" in host else "https://" + host
    verify: object = True
    if cfg["CTVL_INSECURE_TLS"].lower() in ("1", "true", "yes"):
        verify = False
    elif cfg["CTVL_CA_BUNDLE"]:
        for cand in (Path(cfg["CTVL_CA_BUNDLE"]), Path(base.get("_dir", ".")) / cfg["CTVL_CA_BUNDLE"],
                     *(r / cfg["CTVL_CA_BUNDLE"] for r in raizes_sindras())):
            if cand.is_file():
                verify = str(cand)
                break
    try:
        timeout = max(60.0, float(cfg["CTVL_TIMEOUT_SECONDS"] or 60))
    except ValueError:
        timeout = 60.0
    registrar_segredo(url)
    registrar_segredo(host.split("://")[-1])
    return {"url": url, "verify": verify, "timeout": timeout}


def senhas_do_ambiente() -> dict[str, str]:
    """usuario -> senha; levanta ErroCofre('config') listando SO os nomes das variaveis ausentes."""
    ausentes = [nome_var_senha(u) for u in USUARIOS if not os.environ.get(nome_var_senha(u))]
    if ausentes:
        raise ErroCofre("config", "variaveis ausentes: " + ", ".join(ausentes))
    senhas = {u: os.environ[nome_var_senha(u)] for u in USUARIOS}
    for s in senhas.values():
        registrar_segredo(s)
    return senhas
