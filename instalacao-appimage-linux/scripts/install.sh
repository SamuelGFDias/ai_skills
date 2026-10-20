#!/usr/bin/env bash
# Instala um AppImage no Linux: copia para ~/Applications, extrai ícones e .desktop
# do próprio AppImage, cria o atalho do menu e valida. NÃO abre o app (ver SKILL.md).
#
# uso: install.sh <arquivo.AppImage> <nome-curto> [app-id]
#   nome-curto: nome do arquivo e do atalho (ex.: t3code) — sem espaços
#   app-id:     StartupWMClass da janela (ex.: com.t3tools.T3Code). Padrão: nome-curto.
#               Descubra-o depois do primeiro início, ver SKILL.md, passo 6.
set -euo pipefail

SRC=${1:-}
NAME=${2:-}
APPID=${3:-$NAME}

if [ -z "$SRC" ] || [ -z "$NAME" ]; then
  echo "uso: $0 <arquivo.AppImage> <nome-curto> [app-id]" >&2
  exit 2
fi
if [ ! -f "$SRC" ]; then
  echo "arquivo não encontrado: $SRC" >&2
  exit 1
fi

# AppImage tipo 2 tem a assinatura "AI" no byte 8. Sem ela, não é AppImage.
if [ "$(dd if="$SRC" bs=1 skip=8 count=2 2>/dev/null)" != "AI" ]; then
  echo "não parece um AppImage (assinatura 'AI' ausente): $SRC" >&2
  exit 1
fi

APPS_DIR="$HOME/Applications"
DEST="$APPS_DIR/$NAME.AppImage"
ICON_ROOT="$HOME/.local/share/icons/hicolor"
DESKTOP_DIR="$HOME/.local/share/applications"

echo "==> 1. Copiando para $DEST"
mkdir -p "$APPS_DIR"
cp -f "$SRC" "$DEST"
chmod +x "$DEST"

echo "==> 2. Verificando o runtime"
"$DEST" --appimage-version

echo "==> 3. Checando FUSE (libfuse.so.2)"
if ldconfig -p | grep -q 'libfuse\.so\.2'; then
  echo "libfuse.so.2 presente"
else
  echo "AVISO: libfuse.so.2 ausente. Se o app não abrir, instale o pacote de FUSE 2" >&2
  echo "       (Fedora: sudo dnf install -y fuse-libs | Debian/Ubuntu: sudo apt install libfuse2t64 ou libfuse2)" >&2
  echo "       ou rode com --appimage-extract-and-run (não exige FUSE)." >&2
fi

echo "==> 4. Extraindo .desktop e ícones para diretório temporário próprio"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
(
  cd "$WORK"
  # Só lê o que precisa. Nada do conteúdo extraído é executado.
  "$DEST" --appimage-extract '*.desktop' >/dev/null 2>&1 || true
  "$DEST" --appimage-extract '*.png' >/dev/null 2>&1 || true
  "$DEST" --appimage-extract 'usr/share/icons/*' >/dev/null 2>&1 || true
)
ROOT="$WORK/squashfs-root"
if [ ! -d "$ROOT" ]; then
  echo "falha ao extrair de $DEST (--appimage-extract)" >&2
  exit 1
fi

DESKTOP_SRC=$(find "$ROOT" -maxdepth 1 -name '*.desktop' | head -1)
if [ -z "$DESKTOP_SRC" ]; then
  echo "nenhum .desktop dentro do AppImage" >&2
  exit 1
fi

ICON_NAME=$(sed -n 's/^Icon=//p' "$DESKTOP_SRC" | head -1)
ICON_NAME=${ICON_NAME:-$NAME}

echo "==> 5. Instalando ícones (tema hicolor, nome '$ICON_NAME')"
ICON_COUNT=0
for src in "$ROOT"/usr/share/icons/hicolor/*/apps/"$ICON_NAME".png; do
  [ -f "$src" ] || continue
  size=$(basename "$(dirname "$(dirname "$src")")")
  mkdir -p "$ICON_ROOT/$size/apps"
  cp -f "$src" "$ICON_ROOT/$size/apps/$ICON_NAME.png"
  ICON_COUNT=$((ICON_COUNT + 1))
done
if [ "$ICON_COUNT" -eq 0 ] && [ -f "$ROOT/$ICON_NAME.png" ]; then
  # Sem tema hicolor: usa o PNG da raiz como 512x512 (tamanho do ícone principal).
  mkdir -p "$ICON_ROOT/512x512/apps"
  cp -f "$ROOT/$ICON_NAME.png" "$ICON_ROOT/512x512/apps/$ICON_NAME.png"
  ICON_COUNT=1
fi
if [ "$ICON_COUNT" -eq 0 ]; then
  echo "AVISO: nenhum ícone encontrado; o atalho ficará sem ícone" >&2
fi
echo "$ICON_COUNT tamanho(s) instalado(s)"

echo "==> 6. Criando o atalho do menu $DESKTOP_DIR/$NAME.desktop"
mkdir -p "$DESKTOP_DIR"
DESKTOP_DEST="$DESKTOP_DIR/$NAME.desktop"
sed -e "s|^Exec=.*|Exec=$DEST %U|" \
    -e "s|^Icon=.*|Icon=$ICON_NAME|" \
    -e "/^StartupWMClass=/d" \
    "$DESKTOP_SRC" > "$DESKTOP_DEST"
# StartupWMClass deve ser o app-id que a janela registra. Sem isso, a dock mostra
# o atalho fixado e a janela aberta como dois ícones diferentes.
echo "StartupWMClass=$APPID" >> "$DESKTOP_DEST"

echo "==> 7. Validando"
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$DESKTOP_DEST"
  echo "desktop-file-validate OK"
else
  echo "desktop-file-validate ausente (pulado)"
fi
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t -f "$ICON_ROOT" 2>/dev/null || true

echo
echo "Instalado: $DEST"
echo "Atalho:    $DESKTOP_DEST"
echo "Próximo passo: abra o app UMA vez pelo menu e rode o passo 6 de SKILL.md"
echo "para confirmar o app-id. NÃO teste com 'timeout': ver passo 8 de SKILL.md."
