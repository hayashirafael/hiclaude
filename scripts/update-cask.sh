#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Gera Casks/hiclaude.rb a partir da versão + sha256 do DMG. Usado tanto no
# release CI (que empurra pro tap hayashirafael/homebrew-tap) quanto localmente
# pra conferir o cask antes de publicar. Mantém o .rb reproduzível — nunca
# editado à mão.
VERSION="${1:?uso: update-cask.sh <versao> <caminho-do-dmg> [dir-de-saida]}"
DMG="${2:?uso: update-cask.sh <versao> <caminho-do-dmg> [dir-de-saida]}"
OUT_DIR="${3:-Casks}"

[[ -f "$DMG" ]] || { echo "erro: DMG não encontrado: $DMG"; exit 1; }

SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"
mkdir -p "$OUT_DIR"
CASK="$OUT_DIR/hiclaude.rb"

cat > "$CASK" <<RUBY
# typed: strict
# frozen_string_literal: true

cask "hiclaude" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/hayashirafael/hiclaude/releases/download/v#{version}/HiClaude-#{version}.dmg"
  name "HiClaude"
  desc "Menu bar app that opens the Claude plan's 5-hour usage window on a schedule"
  homepage "https://github.com/hayashirafael/hiclaude"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "HiClaude.app"

  zap trash: "~/Library/Preferences/dev.hiclaude.HiClaude.plist"

  caveats <<~EOS
    HiClaude is ad-hoc signed (not notarized — no paid Apple Developer account).
    On first launch, macOS Gatekeeper will block it. To open it:

      System Settings → Privacy & Security → "Open Anyway"

    or clear the quarantine flag yourself:

      xattr -dr com.apple.quarantine "#{appdir}/HiClaude.app"
  EOS
end
RUBY

echo "Gerado: $CASK (sha256 $SHA256)"
