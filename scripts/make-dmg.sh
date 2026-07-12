#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Builda o .app (com ícone, ad-hoc signed) e empacota num DMG de arrastar-para-
# Applications — o formato padrão de instalador de apps macOS fora da App Store.
./scripts/make-app.sh

APP="build/Ohayo.app"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" scripts/Info.plist)"
DMG="build/Ohayo-${VERSION}.dmg"
rm -f "$DMG"

# Staging limpo: só o app (o symlink para /Applications é adicionado abaixo),
# senão o DMG carregaria lixo do diretório build/.
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"

if command -v create-dmg >/dev/null 2>&1; then
    # create-dmg (Homebrew): janela estilizada com o app e o atalho Applications
    # posicionados. --hdiutil-quiet evita ruído; retorno 2 = "sem code-sign", ok.
    create-dmg \
        --volname "Ohayo" \
        --window-pos 200 120 \
        --window-size 600 380 \
        --icon-size 100 \
        --icon "Ohayo.app" 150 190 \
        --app-drop-link 450 190 \
        --hide-extension "Ohayo.app" \
        "$DMG" "$STAGING" || true
else
    echo "aviso: create-dmg não encontrado (brew install create-dmg) — DMG simples via hdiutil"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "Ohayo" -srcfolder "$STAGING" \
        -ov -format UDZO "$DMG" >/dev/null
fi

rm -rf "$STAGING"
[[ -f "$DMG" ]] || { echo "erro: DMG não foi gerado"; exit 1; }
echo "Gerado: $DMG"
