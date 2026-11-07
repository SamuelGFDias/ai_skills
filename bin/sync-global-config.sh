#!/usr/bin/env bash
# sync-global-config.sh — mantém, no diretório global de cada agente, as instruções de uso das
# skills que você escolheu (só bash; sem par .ps1).
#
# Cada skill pode ter um `global.md` na sua pasta, e há snippets avulsos em bin/global/*.md. O
# id de cada snippet é o nome da pasta da skill ou o nome do arquivo. A primeira linha pode ser
# `<!-- desc: texto -->` (aparece na pergunta; é removida do conteúdo gerado).
#
# Seleção (por máquina, fora do repo): ~/.config/ai/skills-global.conf  (AI_SKILLS_CONFIG_DIR muda a pasta)
#   +<id>   ligado
#   -<id>   desligado
#   Snippet sem linha no arquivo é "novo": o script pergunta (precisa de terminal).
#
# Como o conteúdo chega ao agente:
#   claude, gemini  -> o conteúdo vai para <dir-global>/ai-skills.md e o CLAUDE.md/GEMINI.md ganha
#                      só um bloco com `@ai-skills.md` (esses CLIs importam arquivo).
#   codex, opencode -> esses CLIs não importam arquivo (conferido na documentação): o conteúdo vai
#                      inline, num bloco delimitado, no AGENTS.md.
# Os blocos usam marcadores "BEGIN/END ai-skills:<nome>"; o resto do arquivo nunca é tocado. Os
# blocos antigos (delegacao-t3, uso-skills) são removidos na migração.
#
# Uso:
#   bin/sync-global-config.sh [claude|codex|gemini|opencode|all] [--choose] [--yes] [--list] [--dry-run]
#     --choose   pergunta de novo por todos os snippets (não só os novos)
#     --yes      não pergunta: snippet sem escolha salva entra ligado (S). Escolhas já salvas não
#                mudam, nem com --choose
#     --list     mostra os snippets e o estado salvo, sem alterar nada
#     --dry-run  mostra o que faria; não pergunta, não grava seleção nem arquivos
#   Sem terminal (stdin/stdout não-tty) o script não pergunta. Enquanto algum snippet estiver sem
#   decisão salva, ele não altera arquivo nenhum (só avisa): a migração apagaria os blocos antigos
#   sem pôr nada no lugar. Com --yes isso não acontece: o padrão S é gravado e o arquivo é atualizado.
#   kilo não tem arquivo global mapeado: aceito só para não quebrar quem o passa; não faz nada.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_DIR="${AI_SKILLS_CONFIG_DIR:-$HOME/.config/ai}"
CONF_FILE="$CONF_DIR/skills-global.conf"
MODE="apply"
CHOOSE=0
YES=0
LIST=0
CLIS=()

log() { echo ">> $*"; }
die() { echo "ERRO: $*" >&2; exit 2; }

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

for a in "$@"; do
  case "$a" in
    --dry-run) MODE="dry-run" ;;
    --choose) CHOOSE=1 ;;
    --yes|-y) YES=1 ;;
    --list) LIST=1 ;;
    -h|--help) usage; exit 0 ;;
    claude|codex|gemini|opencode|kilo|all) CLIS+=("$a") ;;
    *) die "argumento desconhecido: $a (use --help)" ;;
  esac
done
[ "${#CLIS[@]}" -gt 0 ] || CLIS=(all)

# ---------- snippets ----------

# imprime "id<TAB>arquivo", um por linha
candidates() {
  local f d
  for f in "$REPO_DIR"/*/global.md; do
    [ -f "$f" ] || continue
    d="$(dirname "$f")"
    [ -f "$d/SKILL.md" ] || continue
    printf '%s\t%s\n' "$(basename "$d")" "$f"
  done
  for f in "$REPO_DIR"/bin/global/*.md; do
    [ -f "$f" ] || continue
    printf '%s\t%s\n' "$(basename "$f" .md)" "$f"
  done
}

desc_of() { sed -n '1s/^<!-- desc: \(.*\) -->$/\1/p' "$1"; }
body_of() { sed '1{/^<!-- desc: .* -->$/d;}' "$1"; }

state_of() {
  local id="$1"
  if [ -f "$CONF_FILE" ] && grep -qxF "+$id" "$CONF_FILE"; then echo enabled
  elif [ -f "$CONF_FILE" ] && grep -qxF -- "-$id" "$CONF_FILE"; then echo disabled
  else echo unknown; fi
}

set_state() {
  local id="$1" sign="$2" tmp
  mkdir -p "$CONF_DIR"
  tmp="$(mktemp)"
  if [ -f "$CONF_FILE" ]; then grep -vxF -e "+$id" -e "-$id" "$CONF_FILE" > "$tmp" || true; fi
  printf '%s%s\n' "$sign" "$id" >> "$tmp"
  mv "$tmp" "$CONF_FILE"
}

is_tty() { [ -t 0 ] && [ -t 1 ]; }

# Pergunta por snippet novo (ou todos, com --choose). Só roda com terminal e fora do dry-run.
choose_snippets() {
  local id file st desc cur ans unknown=0
  while IFS=$'\t' read -r id file; do
    st="$(state_of "$id")"
    if [ "$CHOOSE" -eq 0 ] && [ "$st" != unknown ]; then continue; fi
    desc="$(desc_of "$file")"
    cur="s"; [ "$st" = disabled ] && cur="n"
    printf '  %s%s\n    ligar? [s/n] (Enter = %s) ' "$id" "${desc:+ — $desc}" "$cur" > /dev/tty
    read -r ans < /dev/tty || ans=""
    case "$ans" in
      s|S|y|Y) set_state "$id" "+" ;;
      n|N) set_state "$id" "-" ;;
      "") if [ "$cur" = s ]; then set_state "$id" "+"; else set_state "$id" "-"; fi ;;
      *) echo "    resposta inválida: mantendo '$cur'" > /dev/tty
         if [ "$cur" = s ]; then set_state "$id" "+"; else set_state "$id" "-"; fi ;;
    esac
  done < <(candidates)
}

# Com --yes: snippet sem escolha salva entra ligado (padrão S), sem perguntar e sem terminal.
auto_choose_snippets() {
  local id file
  while IFS=$'\t' read -r id file; do
    if [ "$(state_of "$id")" = unknown ]; then set_state "$id" "+"; fi
  done < <(candidates)
}

unresolved_count() {
  local id file n=0
  while IFS=$'\t' read -r id file; do
    [ "$(state_of "$id")" = unknown ] && n=$((n + 1))
  done < <(candidates)
  echo "$n"
}

warn_unknown() {
  local id file ids=""
  while IFS=$'\t' read -r id file; do
    [ "$(state_of "$id")" = unknown ] && ids="$ids $id"
  done < <(candidates)
  [ -z "$ids" ] || echo "AVISO: snippet(s) sem escolha salva:$ids" >&2
}

enabled_count() {
  local id file n=0
  while IFS=$'\t' read -r id file; do
    [ "$(state_of "$id")" = enabled ] && n=$((n + 1))
  done < <(candidates)
  echo "$n"
}

# conteúdo gerado: o corpo de cada snippet ligado, separados por linha em branco
compose() {
  local id file n=0
  while IFS=$'\t' read -r id file; do
    [ "$(state_of "$id")" = enabled ] || continue
    [ "$n" -eq 0 ] || echo
    body_of "$file"
    n=$((n + 1))
  done < <(candidates)
}

# ---------- blocos num arquivo ----------

# remove_block_to <arquivo> <nome>: imprime o arquivo sem o bloco (e sem a linha em branco que o precedia)
remove_block_to() {
  [ -f "$1" ] || return 0
  awk -v b="<!-- BEGIN ai-skills:$2" -v e="<!-- END ai-skills:$2 -->" '
    function flush() { if (held) { print ""; held = 0 } }
    index($0, b) == 1 { held = 0; skip = 1; next }
    skip { if (index($0, e) == 1) skip = 0; next }
    /^$/ { flush(); held = 1; next }
    { flush(); print }
    END { flush() }
  ' "$1"
}

# upsert_block_to <arquivo> <nome> <arquivo-do-bloco>: troca o bloco no lugar, ou acrescenta ao fim
upsert_block_to() {
  local f="$1" name="$2" blk="$3"
  if [ -f "$f" ] && grep -qF "<!-- BEGIN ai-skills:$name" "$f"; then
    awk -v b="<!-- BEGIN ai-skills:$name" -v e="<!-- END ai-skills:$name -->" -v src="$blk" '
      index($0, b) == 1 { if (!done) { while ((getline line < src) > 0) print line; close(src); done = 1 } skip = 1; next }
      skip { if (index($0, e) == 1) skip = 0; next }
      { print }
    ' "$f"
  else
    if [ -f "$f" ]; then cat "$f"; [ -s "$f" ] && printf '\n'; fi
    cat "$blk"
  fi
}

# ---------- por CLI ----------

# define DIR, FILE, IMPORT (1 = o CLI importa arquivo)
target_for() {
  case "$1" in
    claude)   DIR="$HOME/.claude";          FILE="CLAUDE.md"; IMPORT=1 ;;
    codex)    DIR="$HOME/.codex";           FILE="AGENTS.md"; IMPORT=0 ;;
    gemini)   DIR="$HOME/.gemini";          FILE="GEMINI.md"; IMPORT=1 ;;
    opencode) DIR="$HOME/.config/opencode"; FILE="AGENTS.md"; IMPORT=0 ;;
    *) return 1 ;;
  esac
}

installed() {
  case "$1" in
    gemini) command -v gemini >/dev/null 2>&1 || command -v agy >/dev/null 2>&1 ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}

sync_cli() {
  local cli="$1" target managed count cur out blk composed changed=0
  target_for "$cli" || return 0
  target="$DIR/$FILE"; managed="$DIR/ai-skills.md"

  # opencode só lê ~/.claude/CLAUDE.md como fallback quando o AGENTS.md próprio não existe:
  # criar esse AGENTS.md faria o opencode ignorar o CLAUDE.md do usuário.
  if [ "$cli" = "opencode" ] && [ ! -f "$target" ] && [ -f "$HOME/.claude/CLAUDE.md" ]; then
    log "opencode: $target não existe e ~/.claude/CLAUDE.md já cobre o opencode (fallback); nada a fazer"
    return 0
  fi

  count="$(enabled_count)"
  composed="$(compose)"
  cur="$(mktemp)"; [ -f "$target" ] && cp "$target" "$cur"

  step() { out="$(mktemp)"; "$@" > "$out"; mv "$out" "$cur"; }   # step <fn> <args...>: aplica sobre $cur

  # migração: blocos antigos gerados pelo install.sh
  step remove_block_to "$cur" delegacao-t3
  step remove_block_to "$cur" uso-skills

  local want_managed=0
  if [ "$count" -eq 0 ]; then
    step remove_block_to "$cur" global
    step remove_block_to "$cur" import
  elif [ "$IMPORT" -eq 1 ]; then
    step remove_block_to "$cur" global
    blk="$(mktemp)"
    printf '%s\n%s\n%s\n' \
      "<!-- BEGIN ai-skills:import (gerenciado por bin/sync-global-config.sh; edite o global.md da skill, não este bloco) -->" \
      "@ai-skills.md" \
      "<!-- END ai-skills:import -->" > "$blk"
    step upsert_block_to "$cur" import "$blk"; rm -f "$blk"
    want_managed=1
  else
    step remove_block_to "$cur" import
    blk="$(mktemp)"
    { printf '%s\n' "<!-- BEGIN ai-skills:global (gerenciado por bin/sync-global-config.sh; edite o global.md da skill, não este bloco) -->"
      printf '%s\n' "$composed"
      printf '%s\n' "<!-- END ai-skills:global -->"; } > "$blk"
    step upsert_block_to "$cur" global "$blk"; rm -f "$blk"
  fi

  # arquivo gerenciado (só nos CLIs com import)
  if [ "$want_managed" -eq 1 ]; then
    local newm; newm="$(mktemp)"
    { echo "<!-- gerado por bin/sync-global-config.sh; não edite (edite o global.md da skill e rode o script) -->"
      echo
      printf '%s\n' "$composed"; } > "$newm"
    if [ ! -f "$managed" ] || ! cmp -s "$newm" "$managed"; then
      log "$cli: gravando $managed ($count snippet(s))"; changed=1
      [ "$MODE" = "apply" ] && { mkdir -p "$DIR"; mv "$newm" "$managed"; newm=""; }
    fi
    [ -z "$newm" ] || rm -f "$newm"
  elif [ -f "$managed" ]; then
    log "$cli: removendo $managed (sem import ou sem snippets ligados)"; changed=1
    [ "$MODE" = "apply" ] && rm -f "$managed"
  fi

  # agente: só escreve se mudou; arquivo inexistente e sem nada para pôr não é criado
  if [ -f "$target" ] && cmp -s "$cur" "$target"; then
    :
  elif [ ! -f "$target" ] && [ ! -s "$cur" ]; then
    :
  else
    log "$cli: atualizando $target"; changed=1
    [ "$MODE" = "apply" ] && { mkdir -p "$DIR"; cp "$cur" "$target"; }
  fi
  rm -f "$cur"
  [ "$changed" -eq 1 ] || log "$cli: $target já está em dia"
}

# ---------- main ----------

if [ "$LIST" -eq 1 ]; then
  echo "Seleção: $CONF_FILE"
  while IFS=$'\t' read -r id file; do
    printf '  %-10s %-26s %s\n' "$(state_of "$id")" "$id" "$(desc_of "$file")"
  done < <(candidates)
  exit 0
fi

if [ "$MODE" = "apply" ] && [ "$YES" -eq 1 ]; then
  auto_choose_snippets
elif [ "$MODE" = "apply" ] && is_tty; then
  choose_snippets
elif [ "$MODE" = "apply" ] && [ "$CHOOSE" -eq 1 ]; then
  echo "AVISO: --choose precisa de terminal; ignorado." >&2
fi

# Enquanto houver snippet sem decisão, nada é alterado: a migração removeria os blocos antigos sem
# pôr nada no lugar, e o usuário ficaria sem as instruções até escolher.
if [ "$(unresolved_count)" -gt 0 ]; then
  warn_unknown
  echo "Nada alterado: escolha os snippets acima (terminal ou --choose) e rode de novo."
  exit 0
fi

targets=()
for c in "${CLIS[@]}"; do
  if [ "$c" = "all" ]; then
    for k in claude codex gemini opencode; do installed "$k" && targets+=("$k"); done
  elif [ "$c" = "kilo" ]; then
    log "kilo: sem arquivo global mapeado; nada a fazer"
  else
    targets+=("$c")
  fi
done
[ "${#targets[@]}" -gt 0 ] || { echo "Nenhum CLI suportado encontrado no PATH. Nada a fazer."; exit 0; }

for cli in "${targets[@]}"; do sync_cli "$cli"; done
echo "Feito ($MODE)."
