# HiClaude

**English** | [Português](README.pt-br.md)

macOS menu bar app that fires `claude -p` on a schedule to open the Claude plan's
5-hour usage window — and skips the run if a window is already active. Swift + SwiftUI
(`MenuBarExtra`), no external dependencies.

## Requirements

- macOS 13+
- [Claude Code](https://claude.com/claude-code) installed and logged in (the `claude` binary on `PATH`)
- To build from source: Swift 5.9+ (Xcode or Command Line Tools)

## Install

### Homebrew

```bash
brew tap hayashirafael/tap
brew trust --cask hayashirafael/tap/hiclaude
brew install --cask hiclaude
```

To update later:

```bash
brew upgrade --cask hiclaude
```

HiClaude is ad-hoc signed, not notarized. On first launch, macOS Gatekeeper may
block it; use **System Settings → Privacy & Security → Open Anyway** or clear the
quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/HiClaude.app
```

### Release (DMG)

1. Download `HiClaude-<version>.dmg` from the [latest release](../../releases/latest).
2. Open the DMG and drag **HiClaude** onto the **Applications** folder.
3. First launch: right-click the app → **Open** (the build is ad-hoc signed, not
   notarized, so Gatekeeper warns once). Alternatively, clear the quarantine flag:
   ```bash
   xattr -dr com.apple.quarantine /Applications/HiClaude.app
   ```

Once in `/Applications`, HiClaude shows up in Spotlight and Launchpad (search
"HiClaude"), even though it runs only in the menu bar.

### From source

```bash
git clone https://github.com/hayashirafael/hiclaude.git
cd hiclaude
swift test            # runs the test suite
./scripts/make-app.sh # builds build/HiClaude.app (ad-hoc signed, LSUIElement)
./scripts/make-dmg.sh # builds build/HiClaude-<version>.dmg (needs `brew install create-dmg`)
open build/HiClaude.app
```

The app icon is generated at build time from `assets/AppIcon.png` (a single
1024×1024 master); the script derives every `.iconset` size and compiles the `.icns`.

## Usage

Lives in the menu bar (no Dock icon). Click the balloon for the menu:

- **Status** — next run time, `Paused`, or error (CLI not found / failure)
- **Last run** — success, skipped (window already active), or failure
- **Send hi now** — fire manually
- **Pause / Resume** — suspend scheduled runs
- **Message** — pick the active message to send; **Manage…** opens the config window
- **Schedules…** — open the config window (add/remove/edit times and messages)
- **Start at login** — register as a login item (`SMAppService`)
- **Quit**

Schedules are daily and configurable (default: 07:00). If the Mac was asleep at the
scheduled time, the run fires on wake (catch-up). A failed scheduled run posts a system
notification.

The sent message is configurable: keep a list of favorites and select the active one
from the **Message** submenu. The default (`1+1`) is always available and is used as a
fallback when no valid active message is set.

## How it works

Claude plans (Pro/Max) open a 5-hour usage window from the first prompt. At each
configured time, HiClaude runs:

```
claude -p --model claude-haiku-4-5 --effort low --safe-mode "<active message>"
```

Haiku, low effort, and `--safe-mode` (skips CLAUDE.md/skills/MCP) keep it cheap — just
enough to open the window. The message is the active one you selected (default `1+1`, a
minimal-token ping).

Before firing, it passively reads the local Claude Code transcripts at
`~/.claude/projects/**.jsonl` (streaming line by line, ordered by `mtime`) and
reconstructs the current 5-hour window. If one is already active, the run is skipped.
