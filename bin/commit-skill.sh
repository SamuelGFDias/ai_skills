#!/usr/bin/env bash
# commit-skill.sh — commit de UMA skill: validação, mensagem padronizada e push opcional (só bash; sem par .ps1).
#
# Uso:
#   bin/commit-skill.sh <skill> -m "<descrição>" [--type feat|fix|docs|refactor|chore] [--push] [--yes]
#
# Padrão = DRY-RUN. Mostra a validação (validate-skills.sh --full <skill>), os arquivos que entrariam,
# a mensagem final e o que faria com --push. Não altera nada (nem git add/commit/push, nem symlink).
#
# Com --yes, nesta ordem:
#   1. validate-skills.sh --full <skill>; falha aborta sem alterar nada
#   2. cria ~/.claude/skills/<skill> como symlink se faltar (nunca diretório real; existente não é tocado)
#   3. git add -- <skill> (e README.md, só se alterado)
#   4. git commit -m "<type>(<skill>): <descrição>" -- <skill> [README.md]
#      (pathspec: não leva para o commit o que já estava staged por fora)
#   5. com --push: git push; se rejeitado (rejected / non-fast-forward / fetch first), faz
#      git pull --rebase e tenta o push uma vez; conflito ou nova falha = rebase abortado e relatado
#
# Type padrão: feat se a skill é nova (não existe no HEAD), senão fix.
# Recusa descrição vazia, multilinha ou com atribuição de IA (AGENTS.md, regra 7).
# Nunca usa --no-verify nem --force: flags desconhecidas são recusadas.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROBOT_EMOJI=$'\xf0\x9f\xa4\x96'

usage() {
  cat <<'EOF'
Uso: bin/commit-skill.sh <skill> -m "<descrição>" [--type feat|fix|docs|refactor|chore] [--push] [--yes]

  (sem --yes)  dry-run: mostra validação, arquivos, mensagem e ação; não altera nada
  --yes        valida, cria symlink se faltar, faz add e commit (sem push)
  --push       com --yes, também faz git push (rebase uma vez se rejeitado)
EOF
  return 0
}

die() {
  echo "ERRO: $*" >&2
  exit 2
}

abortar() {
  echo "ABORTADO: $*" >&2
  exit 1
}

SKILL=""
DESC=""
TYPE=""
DO_PUSH=0
DO_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    -m)
      [ $# -ge 2 ] || die "-m exige a descrição"
      DESC="$2"
      shift
      ;;
    --type)
      [ $# -ge 2 ] || die "--type exige um valor"
      TYPE="$2"
      shift
      ;;
    --push) DO_PUSH=1 ;;
    --yes) DO_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "opção não suportada: $1 (--no-verify e --force não são usados por esta ferramenta)" ;;
    *)
      [ -z "$SKILL" ] || die "skill já informada: $SKILL (uma por execução)"
      SKILL="${1%/}"
      ;;
  esac
  shift
done

[ -n "$SKILL" ] || { usage >&2; exit 2; }
[ -f "$REPO_DIR/$SKILL/SKILL.md" ] || die "'$SKILL' não é skill deste repo (sem $SKILL/SKILL.md)"

DESC_TRIM="$(printf '%s' "$DESC" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
[ -n "$DESC_TRIM" ] || die "descrição (-m) vazia"
case "$DESC_TRIM" in
  *$'\n'*) die "descrição deve ter uma linha só" ;;
esac
DESC_LOWER="$(printf '%s' "$DESC_TRIM" | tr '[:upper:]' '[:lower:]')"
case "$DESC_LOWER" in
  *co-authored-by*|*"generated with"*) die "descrição contém atribuição de IA (Co-Authored-By / Generated with); proibido pela regra 7 do AGENTS.md" ;;
esac
case "$DESC_TRIM" in
  *"$ROBOT_EMOJI"*) die "descrição contém emoji de robô (atribuição de IA); proibido pela regra 7 do AGENTS.md" ;;
esac

HEAD_ENTRADA="$(git -C "$REPO_DIR" ls-tree --name-only HEAD -- "$SKILL" 2>/dev/null || true)"
if [ -z "$HEAD_ENTRADA" ]; then
  SKILL_NOVA=1
  TYPE_PADRAO="feat"
else
  SKILL_NOVA=0
  TYPE_PADRAO="fix"
fi
if [ -z "$TYPE" ]; then
  TYPE="$TYPE_PADRAO"
fi
case "$TYPE" in
  feat|fix|docs|refactor|chore) ;;
  *) die "--type inválido: $TYPE (use feat|fix|docs|refactor|chore)" ;;
esac

MSG="$TYPE($SKILL): $DESC_TRIM"

# Arquivos que entrariam (o pathspec ignora o que está staged fora da skill).
SKILL_MUDANCAS="$(git -C "$REPO_DIR" status --porcelain --untracked-files=all -- "$SKILL")"
README_MUDANCA="$(git -C "$REPO_DIR" status --porcelain -- README.md)"
FORA_STAGED="$(git -C "$REPO_DIR" diff --cached --name-only | awk -v s="$SKILL" 'index($0, s "/") == 1 || $0 == "README.md" { next } { print }')"

# Estado do symlink para o Claude Code (mesma regra do validador).
DEST_LINK="$HOME/.claude/skills/$SKILL"
if [ -L "$DEST_LINK" ]; then
  LINK_ALVO="$(cd -P "$DEST_LINK" 2>/dev/null && pwd || true)"
  if [ "$LINK_ALVO" = "$(cd -P "$REPO_DIR/$SKILL" && pwd)" ]; then
    LINK_ESTADO="ok (já aponta para esta skill)"
  else
    LINK_ESTADO="existe e aponta para outro lugar ($(readlink "$DEST_LINK")); não será alterado"
  fi
elif [ -e "$DEST_LINK" ]; then
  LINK_ESTADO="existe como diretório real; não será alterado"
else
  LINK_ESTADO="faltando; seria criado como symlink -> $REPO_DIR/$SKILL"
fi

if [ "$DO_YES" -eq 1 ]; then
  MODO="EXECUÇÃO (--yes)"
else
  MODO="DRY-RUN (nada será alterado; use --yes para commitar)"
fi

echo "== commit-skill: $SKILL — $MODO =="
echo
echo "-- validação: validate-skills.sh --full $SKILL --"
VALID_RC=0
VALID_OUT="$("$REPO_DIR/bin/validate-skills.sh" --full "$SKILL" 2>&1)" || VALID_RC=$?
printf '%s\n' "$VALID_OUT" | sed 's/^/   /'
if [ "$VALID_RC" -eq 0 ]; then
  echo "   validação: PASSOU"
else
  echo "   validação: FALHOU (exit $VALID_RC)"
fi
echo

echo "-- arquivos que entrariam --"
if [ -n "$SKILL_MUDANCAS" ]; then
  printf '%s\n' "$SKILL_MUDANCAS" | sed 's/^/   /'
fi
if [ -n "$README_MUDANCA" ]; then
  printf '%s\n' "$README_MUDANCA" | sed 's/^/   /'
fi
if [ -z "$SKILL_MUDANCAS" ] && [ -z "$README_MUDANCA" ]; then
  echo "   (nenhuma alteração)"
fi
echo "-- já staged fora da skill (NÃO entram neste commit) --"
if [ -n "$FORA_STAGED" ]; then
  printf '%s\n' "$FORA_STAGED" | sed 's/^/   /'
else
  echo "   (nenhum)"
fi
echo

echo "-- mensagem --"
echo "   $MSG"
echo "   (sem trailer de atribuição de IA)"
echo

echo "-- ação --"
echo "   symlink ~/.claude/skills/$SKILL: $LINK_ESTADO"
if [ "$SKILL_NOVA" -eq 1 ]; then
  echo "   skill nova (não existe no HEAD): type padrão feat; README.md precisa citar '$SKILL/'"
fi
echo "   git add -- $SKILL$( [ -n "$README_MUDANCA" ] && printf ' README.md' || true )"
echo "   git commit -m \"$MSG\" -- $SKILL$( [ -n "$README_MUDANCA" ] && printf ' README.md' || true )"
if [ "$DO_PUSH" -eq 1 ]; then
  echo "   git push (origin) apenas se o commit for feito"
else
  echo "   push: NÃO (use --push para publicar)"
fi
echo

if [ "$DO_YES" -eq 0 ]; then
  if [ -z "$SKILL_MUDANCAS" ] && [ -z "$README_MUDANCA" ]; then
    echo "Dry-run: nada a commitar em $SKILL/."
    exit 1
  fi
  echo "Dry-run concluído: nada foi alterado."
  exit "$VALID_RC"
fi

# ----- execução (--yes) -----
if [ "$VALID_RC" -ne 0 ]; then
  abortar "validação falhou; nada foi alterado. Corrija a skill e rode de novo."
fi
if [ -z "$SKILL_MUDANCAS" ]; then
  abortar "não há alteração em $SKILL/ para commitar."
fi

if [ ! -L "$DEST_LINK" ] && [ ! -e "$DEST_LINK" ]; then
  mkdir -p "$HOME/.claude/skills"
  ln -s "$REPO_DIR/$SKILL" "$DEST_LINK"
  echo "symlink criado: $DEST_LINK -> $REPO_DIR/$SKILL"
fi

git -C "$REPO_DIR" add -- "$SKILL"
PATHS=("$SKILL")
if [ -n "$README_MUDANCA" ]; then
  git -C "$REPO_DIR" add -- README.md
  PATHS+=("README.md")
fi

if ! git -C "$REPO_DIR" commit -m "$MSG" -- "${PATHS[@]}"; then
  abortar "git commit falhou (hook ou erro acima). As alterações continuam staged; corrija e rode de novo. Nada foi forçado."
fi
echo "commit criado: $(git -C "$REPO_DIR" log -1 --format='%h %s')"

if [ "$DO_PUSH" -eq 0 ]; then
  echo "push: não feito (rode 'git push' ou use --push)."
  exit 0
fi

if PUSH_OUT="$(git -C "$REPO_DIR" push 2>&1)"; then
  echo "push ok."
  exit 0
fi
echo "push falhou: $PUSH_OUT"
case "$PUSH_OUT" in
  *rejected*|*non-fast-forward*|*"fetch first"*)
    echo "push rejeitado: tentando git pull --rebase (uma vez)."
    ;;
  *)
    abortar "push falhou por motivo que não é rejeição de histórico; não tentei rebase."
    ;;
esac

if ! git -C "$REPO_DIR" pull --rebase; then
  git -C "$REPO_DIR" rebase --abort 2>/dev/null || true
  abortar "git pull --rebase falhou (conflito ou árvore suja). Rebase abortado; resolva manualmente. O commit local está preservado."
fi

if git -C "$REPO_DIR" push; then
  echo "push ok após rebase."
  exit 0
fi
abortar "push falhou de novo após rebase. O commit local está preservado; resolva manualmente."
