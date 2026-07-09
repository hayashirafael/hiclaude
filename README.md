# HiClaude

**English** | [Português](README.pt-br.md)

macOS menu bar app that keeps your Claude plan's 5-hour usage windows always
open — per account, automatically. Swift + SwiftUI (`MenuBarExtra`), no
external dependencies.

## Why

Claude plans (Pro/Max) open a 5-hour usage window from your first prompt. If
you're a heavy user, you want that window already open when you sit down to
work — not to burn its first hour warming up. HiClaude renews each account on
its own, and never fires when a window is already active: it detects the
current window passively from the local Claude Code transcripts, making no
network calls of its own.

## Features

- **Per-account renewal** — Off / **Automatic** (chains 5-hour windows
  continuously) / **Scheduled** (anchored to a daily start time, with a
  natural ~4h overnight break)
- **Multi-account** — detects every `~/.claude*` config dir, shows the
  logged-in email, supports custom aliases
- **Configurable messages** — a Claude prompt with selectable model, effort,
  safe-mode and working directory — or any shell command
- **History** — recent dispatches with status and expandable response
- Global **Pause/Resume** and optional **Launch at Login**

## Requirements

- macOS 13+
- [Claude Code](https://claude.com/claude-code) installed and logged in
- To build from source: Swift 5.9+ (Xcode or Command Line Tools)

## Install

### Homebrew

```bash
brew tap hayashirafael/tap
brew trust --cask hayashirafael/tap/hiclaude
brew install --cask hiclaude   # later: brew upgrade --cask hiclaude
```

### DMG

Download `HiClaude-<version>.dmg` from the
[latest release](../../releases/latest) and drag **HiClaude** onto
**Applications**.

> HiClaude is ad-hoc signed, not notarized. On first launch, Gatekeeper may
> block it: use **System Settings → Privacy & Security → Open Anyway**, or
> clear the quarantine flag with
> `xattr -dr com.apple.quarantine /Applications/HiClaude.app`.

### From source

```bash
git clone https://github.com/hayashirafael/hiclaude.git
cd hiclaude
swift test            # test suite
./scripts/make-app.sh # build/HiClaude.app (ad-hoc signed)
./scripts/make-dmg.sh # build/HiClaude-<version>.dmg (needs `brew install create-dmg`)
open build/HiClaude.app
```

## Usage

HiClaude lives in the menu bar (no Dock icon). The icon is filled while a
renewal is armed, shows `!` on error, and fades when paused; optionally it
also shows the time until the next window expires.

The menu lists each renewing account with its mode, next renewal time and
last dispatch result, plus **Pause/Resume**, **Settings…** and **Quit**.

**Settings** is a sidebar window with four sections:

- **Accounts** — per account: alias, renewal mode (Off / Automatic /
  Scheduled), daily start time (Scheduled only, default 09:00), and which
  message to send (pick from the library or create one inline)
- **Messages** — the message library (Claude prompt or shell command, each
  with its own model/effort/safe-mode/working dir and a "show response"
  toggle)
- **History** — recent dispatches; click a row to read the full response
- **General** — Launch at Login, time remaining in the menu bar

## How it works

Before each dispatch, HiClaude streams the account's local transcripts at
`<account>/projects/**.jsonl` (line by line, ordered by `mtime`) and
reconstructs the current 5-hour window. If one is active, the run is skipped.

A dispatch runs:

```
claude -p --model <model> --effort <effort> [--safe-mode] "<text>"
```

with `CLAUDE_CONFIG_DIR` pinned to the target account. The defaults — Haiku,
low effort, `--safe-mode` (skips CLAUDE.md/skills/MCP) and the message `1+1` —
make it the cheapest possible ping that opens the window. Shell messages run
through your login shell instead.

**Automatic** arms at the end of the detected window and chains the next one.
**Scheduled** fires at the daily anchor + 0/5/10/15h (four windows a day,
leaving the ~4h gap before the next anchor) and catches up dispatches missed
during sleep while their window still applies.
