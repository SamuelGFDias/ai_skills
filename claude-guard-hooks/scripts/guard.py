#!/usr/bin/env python3
"""Hook PreToolUse do Claude Code: guardas determinísticas para Bash, Edit e Write.

Lê o evento JSON do stdin e, se uma regra casar, escreve no stdout a decisão
(`deny` bloqueia e devolve o motivo ao Claude; `ask` mostra o pedido de
permissão normal ao usuário). Sem regra casada, sai 0 sem saída: a chamada segue
o fluxo normal de permissões.

O comando Bash é dividido em segmentos (`&&`, `||`, `;`, `|`, quebra de linha) fora
de aspas, de `$(...)` e de heredoc, e cada regra olha o segmento certo:
- flags (`--no-verify`, `--force`, `--hard`) são procuradas no texto **sem** o
  conteúdo entre aspas, para que uma mensagem de commit que cite a flag não dispare;
- o rodapé de atribuição é procurado só no segmento do próprio `git commit`/`gh pr`,
  inclusive no arquivo de `-F`/`--body-file`.

Falha aberto de propósito: entrada inválida ou erro interno não bloqueiam o
trabalho. As regras são guardas contra deslize, não fronteira de segurança
contra um agente hostil.

Desligar uma regra: env CLAUDE_GUARD_DISABLE com ids separados por vírgula,
ex.: CLAUDE_GUARD_DISABLE=ai-attribution,destructive
"""
import json
import os
import re
import sys

MAX_COMMAND = 64 * 1024  # corta antes das regex: limita o pior caso de tempo
MAX_MSG_FILE = 256 * 1024

AI_ATTRIBUTION = re.compile(
    r"Co-Authored-By:[^\n\"']*(Claude|Anthropic|noreply@anthropic\.com)"
    r"|Generated with \[?Claude Code"
    r"|🤖 Generated with",
    re.IGNORECASE,
)

# `git` seguido de opções globais (-C dir, -c k=v, --no-pager, --git-dir=..., --work-tree=...)
GIT = r"\bgit(?:\s+(?:-C\s+\S+|-c\s+\S+|--no-pager|--git-dir(?:=|\s+)\S+|--work-tree(?:=|\s+)\S+|-P))*\s+"
GIT_COMMIT = re.compile(GIT + r"commit\b")
PR_CREATE = re.compile(r"\bgh\s+pr\s+(create|edit)\b|\bglab\s+mr\s+(create|update)\b")
MSG_FILE = re.compile(r"(?:\s-F\s*|\s--file[=\s]|\s--body-file[=\s]|\s--description-file[=\s])\s*(['\"]?)([^\s'\";|&]+)\1")

PRINTERS = r"(?:cat|tee|head|tail|less|more|xxd|od|base64|strings|echo|printf)"
OP_READ = re.compile(r"\bop\s+read\b")
SECRET_VAR = r"\$\{?(?:BAMBU_ACCESS_CODE|[A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|ACCESS_KEY|PRIVATE_KEY))\b"
PRINT_SECRET_VAR = re.compile(r"^\s*(?:echo|printf|cat)\b.*" + SECRET_VAR, re.S)
PRINTENV_SECRET = re.compile(r"^\s*printenv\s+(?:BAMBU_ACCESS_CODE|[A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|API_KEY))\b")

DB_CLIENT = re.compile(r"^\s*(?:\S*/)?(?:psql|mysql|mariadb|sqlcmd|sqlite3|isql|osql|duckdb|clickhouse-client|mongosh)\b")

# Regras destrutivas, avaliadas no segmento sem o conteúdo entre aspas.
DESTRUCTIVE = [

    (re.compile(GIT + r"push\b(?=.{0,2000}?(?:\s--force(?!-with-lease)\b|\s-[a-zA-Z]*f[a-zA-Z]*\b|\s\+\S))"),
     "git push forçado (use --force-with-lease, ou confirme)"),
    (re.compile(GIT + r"reset\b.{0,2000}?\s--hard\b"), "git reset --hard descarta mudanças não commitadas"),
    (re.compile(GIT + r"clean\b.{0,2000}?\s-[a-zA-Z]*f"), "git clean -f apaga arquivos não rastreados"),
    (re.compile(GIT + r"(?:checkout|restore)\b(?:\s+--)?\s+\.(?:\s|$)"),
     "git checkout/restore do diretório inteiro descarta mudanças"),
    (re.compile(GIT + r"branch\b.{0,2000}?\s-D\b"), "git branch -D apaga branch sem checar merge"),
    (re.compile(r"\b(?:mkfs(?:\.\w+)?|dd\s[^\n]*of=/dev/)"), "formatação ou escrita direta em dispositivo"),
]
RM_BROAD = re.compile(
    r"^\s*(?:sudo\s+)?rm(?=[^\n]{0,400}\s-[a-zA-Z]*[rR]|[^\n]{0,400}\s--recursive)"
    r"(?=[^\n]{0,400}\s-[a-zA-Z]*f|[^\n]{0,400}\s--force)"
    r"[^\n]{0,400}\s[\"']?(?:/|~|\$HOME|\$\{HOME\}|\*|\.\.?)[\"']?/?\*?(?:\s|$)")
SQL_DESTRUCTIVE = [
    (re.compile(r"\b(?:DROP\s+(?:TABLE|DATABASE|SCHEMA)|TRUNCATE\s+(?:TABLE\s+)?\w)", re.I), "DROP/TRUNCATE em banco"),
    (re.compile(r"\bDELETE\s+FROM\s+\w[\w.\"]*\s*(?:;|\"|'|$)", re.I), "DELETE sem WHERE"),
]

SECRET_PATTERNS = [
    (re.compile(r"-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----"), "chave privada"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b"), "token do GitHub"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{60,}\b"), "token do GitHub"),
    (re.compile(r"\bglpat-[A-Za-z0-9_-]{20,}\b"), "token do GitLab"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "chave de acesso da AWS"),
    (re.compile(r"\bsk-ant-[A-Za-z0-9_-]{20,}\b"), "chave da API da Anthropic"),
    (re.compile(r"\bsk-[A-Za-z0-9]{32,}\b"), "chave de API"),
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"), "token do Slack"),
]
SECRET_ALLOWED_PATH = re.compile(r"(\.env\.example|\.env\.sample|/tests?/|/fixtures?/|\.md$)", re.IGNORECASE)


# --- parsing ------------------------------------------------------------------

def split_segments(cmd):
    """Divide em segmentos fora de aspas, $( ), crase e heredoc.

    Devolve lista de (raw, bare, sep_after): `raw` é o texto do segmento, `bare` o
    mesmo texto com o conteúdo entre aspas/$( )/heredoc trocado por espaço, e
    `sep_after` o separador que vem depois ('|', '&&', '||', ';', '\\n' ou '').
    """
    segs, raw, bare = [], [], []
    i, n = 0, len(cmd)
    quote = None      # "'", '"' ou '`'
    depth = 0         # profundidade de $( )
    heredoc = None    # terminador pendente
    pending_heredoc = None

    def flush(sep):
        segs.append(("".join(raw), "".join(bare), sep))
        raw.clear()
        bare.clear()

    while i < n:
        c = cmd[i]
        if heredoc is not None:
            # consome linhas até o terminador
            j = cmd.find("\n", i)
            line = cmd[i:] if j < 0 else cmd[i:j]
            raw.append(cmd[i:] if j < 0 else cmd[i:j + 1])
            bare.append(" ")
            i = n if j < 0 else j + 1
            if line.strip() == heredoc:
                heredoc = None
            continue
        if quote:
            raw.append(c)
            bare.append(" ")
            if c == "\\" and quote == '"' and i + 1 < n:
                raw.append(cmd[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if depth:
            raw.append(c)
            bare.append(" ")
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            elif c in "'\"`":
                # aspas dentro de $( ): pula até fechar
                k = cmd.find(c, i + 1)
                k = n - 1 if k < 0 else k
                raw.append(cmd[i + 1:k + 1])
                bare.append(" ")
                i = k + 1
                continue
            i += 1
            continue
        if c in "'\"`":
            quote = c
            raw.append(c)
            bare.append(" ")
            i += 1
            continue
        if cmd.startswith("$(", i):
            depth = 1
            raw.append("$(")
            bare.append("  ")
            i += 2
            continue
        m = re.match(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", cmd[i:])
        if m:
            pending_heredoc = m.group(2)
            raw.append(m.group(0))
            bare.append(m.group(0))
            i += len(m.group(0))
            continue
        for sep in ("&&", "||", ";", "|", "\n"):
            if cmd.startswith(sep, i):
                if sep == "\n" and pending_heredoc:
                    raw.append("\n")
                    heredoc, pending_heredoc = pending_heredoc, None
                    i += 1
                    break
                flush(sep)
                i += len(sep)
                break
        else:
            raw.append(c)
            bare.append(c)
            i += 1
    flush("")
    return [s for s in segs if s[0].strip()]


def disabled():
    return {x.strip() for x in os.environ.get("CLAUDE_GUARD_DISABLE", "").split(",") if x.strip()}


def decision(kind, reason):
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                   "permissionDecision": kind, "permissionDecisionReason": reason}}


def next_consumer(segs, idx):
    """Comando que recebe por pipe a saída do segmento idx, ou None."""
    if idx + 1 < len(segs) and segs[idx][2] == "|":
        return segs[idx + 1][1].strip()
    return None


def is_printer(cmd):
    return bool(re.match(r"(?:\S*/)?" + PRINTERS + r"\b", cmd or ""))


def read_msg_file(path, cwd):
    try:
        full = path if os.path.isabs(path) else os.path.join(cwd or os.getcwd(), path)
        if path == "-" or not os.path.isfile(full) or os.path.getsize(full) > MAX_MSG_FILE:
            return ""
        with open(full, encoding="utf-8", errors="replace") as f:
            return f.read()
    except Exception:
        return ""


# --- regras ---------------------------------------------------------------------

def check_bash(cmd, off, cwd):
    cmd = cmd[:MAX_COMMAND]
    segs = split_segments(cmd)

    for idx, (raw, bare, _sep) in enumerate(segs):
        is_commit = bool(GIT_COMMIT.search(bare))
        is_pr = bool(PR_CREATE.search(bare))

        if "ai-attribution" not in off and (is_commit or is_pr):
            text = raw
            for m in MSG_FILE.finditer(raw):
                text += "\n" + read_msg_file(m.group(2), cwd)
            if AI_ATTRIBUTION.search(text):
                return decision("deny", "Regra do usuário: commits, PRs e MRs não levam rodapé de atribuição de IA "
                                        "(Co-Authored-By de Claude, 'Generated with Claude Code'). Refaça a mensagem "
                                        "terminando no conteúdo escrito.")

        if "no-verify" not in off and re.search(GIT, bare) and (
                re.search(r"\s--no-verify\b", bare)
                or (is_commit and re.search(r"\s-[a-zA-Z]*n[a-zA-Z]*\b", bare.split("commit", 1)[-1]))):
            return decision("deny", "--no-verify pula os hooks de git do repositório. Corrija o que o hook "
                                    "reclamou em vez de contorná-lo; se for mesmo necessário, peça ao usuário.")

        if "secret-print" not in off:
            consumer = next_consumer(segs, idx)
            piped_safe = consumer is not None and not is_printer(consumer)
            # op read solto no segmento (fora de $( )): imprime, a menos que vá por pipe a um consumidor
            if OP_READ.search(bare) and not piped_safe:
                return decision("deny", "`op read` imprimiria o segredo no transcript. Capture direto numa variável "
                                        "de ambiente, ex.: VAR=\"$(op read 'op://...')\" comando, sem imprimir o valor.")
            # $(op read) como argumento de echo/printf também imprime
            if OP_READ.search(raw) and re.match(r"\s*(?:echo|printf)\b", raw) and not piped_safe:
                return decision("deny", "O comando imprime o resultado de `op read`. Use o valor sem imprimi-lo.")
            if (PRINT_SECRET_VAR.search(raw) or PRINTENV_SECRET.search(raw)) and not piped_safe:
                return decision("deny", "O comando imprime uma variável que parece conter segredo. Use-a sem "
                                        "imprimir (por pipe direto ao consumidor, ex.: | gh auth login --with-token); "
                                        "para conferir, teste só se está definida ([ -n \"$VAR\" ]).")

        if "destructive" not in off:
            if RM_BROAD.search(raw):
                return decision("ask", "Comando destrutivo: rm recursivo e forçado na raiz, na home, no diretório "
                                       "atual, no pai ou com curinga. Confirme antes de rodar.")
            for rx, why in DESTRUCTIVE:
                if rx.search(bare):
                    return decision("ask", f"Comando destrutivo: {why}. Confirme antes de rodar.")
            if DB_CLIENT.search(bare):
                for rx, why in SQL_DESTRUCTIVE:
                    if rx.search(raw):
                        return decision("ask", f"Comando destrutivo: {why}. Confirme antes de rodar.")
    return None


def check_write(tool_input, off):
    if "secret-write" in off:
        return None
    path = str(tool_input.get("file_path", ""))
    if SECRET_ALLOWED_PATH.search(path):
        return None
    text = "\n".join(str(tool_input.get(k, "")) for k in ("content", "new_string"))
    for edit in tool_input.get("edits") or []:
        if isinstance(edit, dict):
            text += "\n" + str(edit.get("new_string", ""))
    for rx, what in SECRET_PATTERNS:
        if rx.search(text[:MAX_COMMAND * 16]):
            return decision("deny", f"O conteúdo parece conter {what}. Segredo não vai para arquivo: leia de um "
                                    "vault (skill vault-factory) ou de variável de ambiente em tempo de execução.")
    return None


def main():
    try:
        event = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(event, dict):
        return 0
    tool = event.get("tool_name", "")
    tool_input = event.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        return 0
    off = disabled()
    result = None
    try:
        if tool == "Bash":
            result = check_bash(str(tool_input.get("command", "")), off, event.get("cwd"))
        elif tool in ("Write", "Edit", "MultiEdit"):
            result = check_write(tool_input, off)
    except Exception:
        return 0
    if result:
        sys.stdout.write(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
