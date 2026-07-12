#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Ohayo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp .build/release/Ohayo "$APP/Contents/MacOS/Ohayo"
cp scripts/Info.plist "$APP/Contents/Info.plist"
# O bundle de recursos (SVGs dos providers) é obrigatório: sem ele o app
# instalado perde os ícones, e um empacotamento silencioso sem o bundle já
# passou despercebido numa release. Falhar alto aqui.
RESOURCE_BUNDLE=".build/release/Ohayo_Ohayo.bundle"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
[[ -d "$APP/Contents/Resources/Ohayo_Ohayo.bundle" ]] || {
    echo "erro: $RESOURCE_BUNDLE ausente — resource bundle não foi empacotado" >&2
    exit 1
}

# Ícone: a partir de um único master 1024x1024 (assets/AppIcon.png), gera todos
# os tamanhos que o macOS exige e compila o .icns. macOS não arredonda sozinho —
# o formato squircle e a margem vão desenhados no próprio PNG.
ICON_MASTER="assets/AppIcon.png"
if [[ -f "$ICON_MASTER" ]]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size"     "$ICON_MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size*2)) $((size*2)) "$ICON_MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET")"
else
    echo "aviso: $ICON_MASTER ausente — app sem ícone (coloque um PNG 1024x1024)"
fi

# Assina por último, depois de Resources/ estar completo.
codesign --force --sign - "$APP"
echo "Gerado: $APP"
