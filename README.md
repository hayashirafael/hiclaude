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

Lives in the menu bar (no Dock icon). The icon fills/empties to reflect the current
5-hour usage window; it shows an error mark if the CLI is not found, and appears faded
if paused.

Click the menu icon for quick actions:

- **Status** — next dispatch time and minutes remaining in the current 5-hour window
- **Renewal lines** (`↻`) — each account's next auto-renewal time
- **Last hi** — clickable when a saved response is available; opens the response
- **Send hi now** — fire a dispatch immediately
- **Pause / Resume** — suspend all scheduled dispatches and auto-renewals (pause affects all accounts)
- **Message** — quick-select the active message to send, or **Manage…** to open Settings
- **Settings…** — open the configuration window
- **Quit**

### Settings Window

The **Settings** window has four tabs:

- **Times** — add/remove/edit daily dispatch times (default: 07:00). Each time can pin a
  message or follow the globally-active message. If the Mac was asleep, the dispatch
  fires on wake (catch-up).
- **Messages** — manage the message list. Set one as active (it's the default at each
  time unless overridden). Each message has a **Show response** toggle to display the
  response in the menu bar after dispatch.
- **History** — view the last 20 dispatches with their times, status, and the sent
  message. Click any row to expand and read the full response.
- **General** — set the default account for dispatches, toggle "Launch at Login"
  (`SMAppService`), display minutes remaining in the menu bar, and enable/disable
  auto-renewal per account.

### Auto-Renewal

When enabled in **General**, each account automatically chains 5-hour usage windows by
sending a default message (`1+1`) every 5 hours. Pause suspends all auto-renewals. The
next renewal time for each account is shown in the menu (e.g., "↻ Renews at 18:00
(.claude)") as informational only.

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
