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

- **Unified agendamentos** — one concept for everything scheduled. Each
  agendamento carries an embedded command and a repetition: **Continuous**
  (chains 5-hour windows 24/7 — the old automatic renewal) or **Fixed times**
  (times × weekdays). Managed in the **Horários** section
- **Configurable commands** — a Claude prompt (model, effort, safe-mode,
  working directory), a Codex prompt (model, reasoning effort), or any shell
  command — embedded directly in the agendamento
- **Multi-account, Claude and Codex** — the default dirs (`~/.claude` and
  `~/.codex`) are always detected; other `~/.claude*` dirs are picked up once,
  on first launch, and from then on you add accounts anytime via
  "Add account…" — shows the logged-in email, supports custom aliases
- **History** — recent dispatches with status and expandable response (full
  error detail on failures)
- Global **Pause/Resume** and optional **Launch at Login**

## Requirements

- macOS 13+
- [Claude Code](https://claude.com/claude-code) installed and logged in
- [Codex CLI](https://github.com/openai/codex) installed and logged in
  (optional, only for Codex accounts/commands)
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
window is active, shows `!` on error, and fades when paused; optionally it
also shows the time until the next window expires.

The menu lists each account with an active agendamento — its next dispatch
time and last result; a line for the next task (if any); plus
**Pause/Resume**, **Settings…** and **Quit**.

**Settings** is a sidebar window with four sections:

- **Accounts** — informative: for each account, the logged-in identity /
  alias, provider, local folder, and how many active agendamentos target it.
  Add or remove accounts here
- **Horários** — the single list of agendamentos. Each has a name, a type
  (Claude / Codex / shell command) with its own config, an account, and a
  repetition — **Continuous** (a 5-hour-window renewal, max one per account)
  or **Fixed times** (times × weekdays). One form creates or edits any of them
- **History** — recent dispatches; click a row to read the full response or
  error detail
- **General** — Launch at Login, time remaining in the menu bar

## How it works

Before each Claude/Codex dispatch, HiClaude streams the account's local
transcripts (`<account>/projects/**.jsonl` for Claude, `sessions/**.jsonl` for
Codex, line by line, ordered by `mtime`) and reconstructs the current 5-hour
window. If one is active, the run is skipped. A Claude window starts at the
top of the hour of its first message (mirroring how the plan counts it); a
Codex window starts at the exact time.

A Claude dispatch runs:

```
claude -p --model <model> --effort <effort> [--safe-mode] "<text>"
```

with `CLAUDE_CONFIG_DIR` pinned to the target account. The defaults — Haiku,
low effort, `--safe-mode` (skips CLAUDE.md/skills/MCP) and the command `1+1` —
make it the cheapest possible ping that opens the window. A Codex dispatch
runs `codex exec [--model <model>] --sandbox read-only [-c
model_reasoning_effort=<effort>] "<text>"` with `CODEX_HOME` pinned instead,
and has its own minimal built-in `1+1` default. When you leave the Codex model
(or reasoning) unset, HiClaude omits the flag so the account's own
`config.toml` default is used — the only value guaranteed to be accepted by
the account's plan. Shell commands run through your login shell.

Which account is Claude vs. Codex is inferred from folder content, not name:
a `.claude.json` or `projects/` subfolder means Claude; an `auth.json` or
`sessions/` subfolder means Codex.

A **Continuous** agendamento arms at the end of the detected window and chains
the next one, 24/7. A **Fixed times** agendamento fires at its times ×
weekdays; on wake (or launch) it fires at most once to catch up the most
recent occurrence it missed — a long sleep never triggers a burst of
backlogged fires. The old *Scheduled* renewal (daily anchor + 0/5/10/15h) is
simply a fixed-times agendamento with four times after migration.
