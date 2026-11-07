#!/usr/bin/env bash
# validate-skills.sh — valida as skills deste repo antes de commit (só bash; sem par .ps1).
#
# Uso:
#   bin/validate-skills.sh [--staged|--full] [skill...]
#
# Alvos:
#   skill...      -> só essas skills (nome do diretório; inexistente = ERRO)
#   --staged      -> skills com mudança staged (git diff --cached)
#   sem argumento -> skills alteradas ou não rastreadas (git diff HEAD + untracked)
#   --full        -> além das checagens por skill, roda `bin/sync-skills.sh all --dry-run`
#                    (somente leitura) e, se arquiteto é alvo, `arquiteto/bin/build-agents.py --check`
#
# Checagens por skill:
#   ERRO  dir sem SKILL.md; frontmatter sem name (igual ao nome do dir, kebab-case) ou com
#         description vazia/em mais de uma linha; falta **Tipo:** no corpo; ~/.claude/skills citado
#         no SKILL.md; segredo em texto claro em *.md (regex do AGENTS.md; o valor nunca é impresso);
#         python3 -I -m py_compile em scripts/*.py; bash -n em scripts/*.sh e bin/*.sh; skill nova
#         (não existe no HEAD) sem menção "<nome>/" no README.md
#   AVISO padrão de segredo em scripts (pode ser falso positivo); caminho absoluto de usuário
#         (/home/<alguém>/) em arquivos da skill; sem symlink
#         ~/.claude/skills/<nome> apontando para a skill
#
# Saída: uma linha por checagem (OK / ERRO / AVISO), resumo final.
# Exit: 0 sem erros (avisos não falham); 1 com algum ERRO; 2 uso inválido.
# Efeitos: não altera arquivos rastreados. Só remove scripts/__pycache__ que o py_compile gera.
set -euo pipefail
shopt -s nullglob

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Regex de segredo do AGENTS.md (seção "Validação antes de commit", item 3), sem \s para portabilidade.
VS_SECRET_RE='(password|secret|token)[[:space:]]*[:=][[:space:]]*["'\''][^"'\'']{6,}'

VS_MODE="default"
VS_FULL=0
VS_ERRORS=0
VS_WARNINGS=0
VS_NAMES=()
VS_TARGETS=()

usage() {
  cat <<'EOF'
Uso: bin/validate-skills.sh [--staged|--full] [skill...]

  skill...      valida só essas skills
  --staged      valida as skills com mudança staged (usado pelo pre-commit)
  (sem args)    valida as skills alteradas ou não rastreadas
  --full        também roda sync-skills --dry-run e, se arquiteto é alvo, build-agents --check
EOF
  return 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --staged) VS_MODE="staged" ;;
    --full) VS_FULL=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
    *) VS_NAMES+=("${1%/}") ;;
  esac
  shift
done

vs_ok() { printf 'OK     %s\n' "$*"; return 0; }
vs_erro() { printf 'ERRO   %s\n' "$*"; VS_ERRORS=$((VS_ERRORS + 1)); return 0; }
vs_aviso() { printf 'AVISO  %s\n' "$*"; VS_WARNINGS=$((VS_WARNINGS + 1)); return 0; }

# vs_fm_value <SKILL.md> <chave> -> valor da chave no frontmatter (vazio se ausente).
vs_fm_value() {
  awk -v k="$2" '
    NR == 1 { if ($0 != "---") exit; infm = 1; next }
    infm && $0 == "---" { exit }
    infm && index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      sub(/^[ \t]+/, "", v); sub(/[ \t\r]+$/, "", v)
      q = substr(v, 1, 1)
      if ((q == "\"" || q == "'\''") && substr(v, length(v), 1) == q) v = substr(v, 2, length(v) - 2)
      print v; exit
    }
  ' "$1"
  return 0
}

# vs_fm_multilinha <SKILL.md> <chave> -> "sim" se o valor é bloco (| ou >) ou continua em linhas indentadas.
vs_fm_multilinha() {
  awk -v k="$2" '
    NR == 1 { if ($0 != "---") exit; infm = 1; next }
    infm && $0 == "---" { exit }
    found && /^[[:space:]]/ { print "sim"; exit }
    found { exit }
    infm && index($0, k ":") == 1 {
      v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v)
      if (v ~ /^[|>]/) { print "sim"; exit }
      found = 1
    }
  ' "$1"
  return 0
}

# vs_skill_novo <skill> -> código 0 se a skill não existe no HEAD.
vs_skill_novo() {
  local no_head
  no_head="$(git -C "$REPO_DIR" ls-tree --name-only HEAD -- "$1" 2>/dev/null || true)"
  if [ -z "$no_head" ]; then
    return 0
  fi
  return 1
}

# vs_alvos -> imprime, uma por linha, os nomes de diretório candidatos (sem validar existência).
vs_alvos() {
  local changed c
  if [ ${#VS_NAMES[@]} -gt 0 ]; then
    for c in "${VS_NAMES[@]}"; do printf '%s\n' "$c"; done
    return 0
  fi
  if [ "$VS_MODE" = "staged" ]; then
    changed="$(git -C "$REPO_DIR" diff --cached --name-only --diff-filter=ACMR)"
  else
    changed="$(git -C "$REPO_DIR" diff --name-only HEAD 2>/dev/null || true)"
    changed="$changed"$'\n'"$(git -C "$REPO_DIR" ls-files --others --exclude-standard)"
  fi
  printf '%s\n' "$changed" | awk -F/ '
    NF > 1 && $1 !~ /^(bin|providers|backend-wiki-skills|\.githooks|\.agents|\.git|\.github)$/ { print $1 }
  ' | sort -u
  return 0
}

# vs_estado_link <skill> -> imprime ok | ausente | outro:<destino> | real
vs_estado_link() {
  local link="$HOME/.claude/skills/$1" alvo_real link_real
  alvo_real="$(cd -P "$REPO_DIR/$1" && pwd)"
  if [ -L "$link" ]; then
    link_real="$(cd -P "$link" 2>/dev/null && pwd || true)"
    if [ "$link_real" = "$alvo_real" ]; then
      echo "ok"
    else
      echo "outro:$(readlink "$link")"
    fi
  elif [ -e "$link" ]; then
    echo "real"
  else
    echo "ausente"
  fi
  return 0
}

vs_check_skill() {
  local skill="$1"
  local dir="$REPO_DIR/$skill"
  local md="$dir/SKILL.md"
  local name desc multi hits out f py_err sh_err pyfiles shfiles

  name="$(vs_fm_value "$md" name)"
  desc="$(vs_fm_value "$md" description)"
  multi="$(vs_fm_multilinha "$md" description)"

  if [ -z "$name" ]; then
    vs_erro "$skill: frontmatter sem 'name' (ou sem frontmatter)"
  elif [ "$name" != "$skill" ]; then
    vs_erro "$skill: name '$name' difere do nome do diretório"
  elif ! [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    vs_erro "$skill: name não é kebab-case"
  else
    vs_ok "$skill: name"
  fi

  if [ -n "$multi" ]; then
    vs_erro "$skill: description em mais de uma linha (use uma linha)"
  elif [ -z "$desc" ]; then
    vs_erro "$skill: description vazia ou ausente"
  else
    vs_ok "$skill: description"
  fi

  if grep -qF '**Tipo:**' "$md"; then
    vs_ok "$skill: **Tipo:** no corpo"
  else
    vs_erro "$skill: falta **Tipo:** no corpo"
  fi

  hits="$(grep -nF '~/.claude/skills' "$md" || true)"
  if [ -n "$hits" ]; then
    vs_erro "$skill: SKILL.md cita ~/.claude/skills (linha $(printf '%s\n' "$hits" | cut -d: -f1 | paste -sd' ' -)); use ~/.config/ai/skills"
  else
    vs_ok "$skill: não cita ~/.claude/skills"
  fi

  hits="$(cd "$REPO_DIR" && grep -rnIiE --exclude-dir=__pycache__ --exclude-dir=node_modules -e "$VS_SECRET_RE" -- "$skill" || true)"
  md_hits="$(printf '%s\n' "$hits" | awk -F: 'NF && $1 ~ /\.md$/ { print }')"
  other_hits="$(printf '%s\n' "$hits" | awk -F: 'NF && $1 !~ /\.md$/ { print }')"
  if [ -n "$md_hits" ]; then
    vs_erro "$skill: possível segredo em texto claro em *.md em $(printf '%s\n' "$md_hits" | cut -d: -f1,2 | paste -sd' ' -) (valor não exibido)"
  elif [ -n "$other_hits" ]; then
    vs_aviso "$skill: padrão de segredo em script em $(printf '%s\n' "$other_hits" | cut -d: -f1,2 | paste -sd' ' -) (revisar; pode ser falso positivo, ex.: substituição de comando; valor não exibido)"
  else
    vs_ok "$skill: sem segredo em texto claro"
  fi

  pyfiles=("$dir"/scripts/*.py)
  py_err=0
  if [ ${#pyfiles[@]} -eq 0 ]; then
    vs_ok "$skill: py_compile (sem scripts/*.py)"
  else
    for f in "${pyfiles[@]}"; do
      if ! out="$(python3 -I -m py_compile "$f" 2>&1)"; then
        vs_erro "$skill: py_compile falhou em ${f#"$REPO_DIR/"}: $(printf '%s\n' "$out" | tail -n 1)"
        py_err=1
      fi
    done
    rm -rf "$dir/scripts/__pycache__"
    if [ "$py_err" -eq 0 ]; then
      vs_ok "$skill: py_compile (${#pyfiles[@]} arquivo(s))"
    fi
  fi

  shfiles=("$dir"/scripts/*.sh "$dir"/bin/*.sh)
  sh_err=0
  if [ ${#shfiles[@]} -eq 0 ]; then
    vs_ok "$skill: bash -n (sem scripts/bin *.sh)"
  else
    for f in "${shfiles[@]}"; do
      if ! out="$(bash -n "$f" 2>&1)"; then
        vs_erro "$skill: bash -n falhou em ${f#"$REPO_DIR/"}: $(printf '%s\n' "$out" | tail -n 1)"
        sh_err=1
      fi
    done
    if [ "$sh_err" -eq 0 ]; then
      vs_ok "$skill: bash -n (${#shfiles[@]} arquivo(s))"
    fi
  fi

  if vs_skill_novo "$skill"; then
    if grep -qE "(^|[^A-Za-z0-9_-])${skill}/" "$REPO_DIR/README.md" 2>/dev/null; then
      vs_ok "$skill: skill nova mencionada no README.md"
    else
      vs_erro "$skill: skill nova sem menção '$skill/' no README.md"
    fi
  else
    vs_ok "$skill: README (não é skill nova)"
  fi

  hits="$(cd "$REPO_DIR" && grep -rnIE --exclude-dir=__pycache__ --exclude-dir=node_modules -e '/home/[^/[:space:]]+/' -- "$skill" || true)"
  if [ -n "$hits" ]; then
    vs_aviso "$skill: caminho absoluto de usuário em $(printf '%s\n' "$hits" | cut -d: -f1 | sort -u | paste -sd' ' -) (use ~ ou caminho relativo)"
  else
    vs_ok "$skill: sem caminho absoluto de usuário"
  fi

  # Valores de uma máquina em skill compartilhada (AGENTS.md, regra 8). Padrões específicos para não
  # pegar placeholders: dotfiles do usuário, op:// com valor real (não <...>) e id real de tailnet.
  hits="$(cd "$REPO_DIR" && grep -rnIE --exclude-dir=__pycache__ --exclude-dir=node_modules -e '\.zshrc\.d|\.zshenv' -e 'op://[^<[:space:]]' -e 'tail[0-9a-f]{5,}\.ts\.net' -- "$skill" || true)"
  if [ -n "$hits" ]; then
    vs_aviso "$skill: valor de máquina em skill compartilhada em $(printf '%s\n' "$hits" | cut -d: -f1,2 | paste -sd' ' -) (use marcador <...> ou mova para providers/; AGENTS.md regra 8)"
  else
    vs_ok "$skill: sem valores de máquina (dotfiles, op://, tailnet)"
  fi

  case "$(vs_estado_link "$skill")" in
    ok) vs_ok "$skill: symlink ~/.claude/skills/$skill" ;;
    ausente) vs_aviso "$skill: falta symlink ~/.claude/skills/$skill (rode bin/sync-skills.sh claude)" ;;
    real) vs_aviso "$skill: ~/.claude/skills/$skill é diretório real, não symlink (ok só no modo cópia do Windows)" ;;
    outro:*) vs_aviso "$skill: ~/.claude/skills/$skill aponta para outro lugar ($(vs_estado_link "$skill" | cut -d: -f2-))" ;;
  esac
  return 0
}

vs_check_full() {
  local out
  if out="$(bash "$REPO_DIR/bin/sync-skills.sh" all --dry-run 2>&1)"; then
    vs_ok "sync-skills: all --dry-run (somente leitura)"
  else
    vs_erro "sync-skills: all --dry-run falhou: $(printf '%s\n' "$out" | tail -n 2 | paste -sd' ' -)"
  fi
  return 0
}

vs_check_arquiteto() {
  local out
  if out="$(cd "$REPO_DIR" && python3 arquiteto/bin/build-agents.py --check 2>&1)"; then
    vs_ok "arquiteto: build-agents.py --check (dist/ em dia)"
  else
    vs_erro "arquiteto: build-agents.py --check falhou (dist/ defasado; rode build-agents.py e commite dist/): $(printf '%s\n' "$out" | tail -n 1)"
  fi
  return 0
}

main() {
  local alvo
  while IFS= read -r alvo; do
    [ -n "$alvo" ] || continue
    if [ ! -d "$REPO_DIR/$alvo" ]; then
      if [ ${#VS_NAMES[@]} -gt 0 ]; then
        vs_erro "$alvo: skill não existe neste repo"
      fi
      continue
    fi
    if [ ! -f "$REPO_DIR/$alvo/SKILL.md" ]; then
      vs_erro "$alvo: dir sem SKILL.md"
      continue
    fi
    VS_TARGETS+=("$alvo")
  done <<< "$(vs_alvos)"

  if [ ${#VS_TARGETS[@]} -eq 0 ]; then
    echo "Nenhuma skill alvo."
    echo "Resumo: 0 skill(s) validada(s), $VS_ERRORS erro(s), $VS_WARNINGS aviso(s)."
    exit 0
  fi

  local s arq=0
  for s in "${VS_TARGETS[@]}"; do
    vs_check_skill "$s"
    if [ "$s" = "arquiteto" ]; then arq=1; fi
  done

  if [ "$VS_FULL" -eq 1 ]; then
    vs_check_full
    if [ "$arq" -eq 1 ]; then
      vs_check_arquiteto
    fi
  fi

  echo "Resumo: ${#VS_TARGETS[@]} skill(s) validada(s), $VS_ERRORS erro(s), $VS_WARNINGS aviso(s)."
  if [ "$VS_ERRORS" -eq 0 ]; then
    exit 0
  fi
  exit 1
}

main
