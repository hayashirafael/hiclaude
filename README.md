# HiYashi

**English** | [Português](README.pt-br.md)

macOS menu bar app that keeps your Claude plan's 5-hour usage windows always
open — per account, automatically. Swift + SwiftUI (`MenuBarExtra`), no
external dependencies.

## Why

Claude plans (Pro/Max) open a 5-hour usage window from your first prompt. If
you're a heavy user, you want that window already open when you sit down to
work — not to burn its first hour warming up. HiYashi renews each account on
its own, and continuous renewal never fires redundantly while a window is
already active: it detects the current window passively from the local Claude
Code transcripts, making no network calls of its own.

## Features

- **Unified schedules** — one concept for everything scheduled. Each
  schedule carries an embedded command and a repetition: **Continuous**
  (chains 5-hour windows 24/7 — the old automatic renewal) or **Fixed times**
  (times × weekdays). Managed in the **Schedules** section
- **Configurable commands** — a Claude prompt (model, effort, safe-mode,
  working directory), a Codex prompt (model, reasoning effort, working
  directory), or any shell command — embedded directly in the schedule.
  Claude/Codex prompts open in Terminal.app by default so you can keep
  interacting in the same session; turn that off to run them in batch mode
- **Multi-account, Claude and Codex** — the default dirs (`~/.claude`,
  `~/.codex`) are picked up automatically when they exist; other `~/.claude*`
  dirs are detected once, on first launch, and from then on you add accounts
  anytime via "Add account…" — shows the logged-in email, supports custom
  aliases
- **History** — recent dispatches with status and expandable response (full
  error detail on failures); optional macOS notifications on failures and
  responses, plus opt-in success notifications per schedule
- **Language** — English by default, with a Portuguese option in Settings
- Per-account **Pause/Resume**, in **Accounts**, and optional **Launch at
  Login**

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

Download `HiYashi-<version>.dmg` from the
[latest release](../../releases/latest) and drag **HiYashi** onto
**Applications**.

> HiYashi is ad-hoc signed, not notarized. On first launch, Gatekeeper may
> block it: use **System Settings → Privacy & Security → Open Anyway**, or
> clear the quarantine flag with
> `xattr -dr com.apple.quarantine /Applications/HiYashi.app`.

### From source

```bash
git clone https://github.com/hayashirafael/hiclaude.git
cd hiclaude
swift test            # test suite
./scripts/make-app.sh # build/HiYashi.app (ad-hoc signed)
./scripts/make-dmg.sh # build/HiYashi-<version>.dmg (needs `brew install create-dmg`)
open build/HiYashi.app
```

## Usage

HiYashi lives in the menu bar (no Dock icon). The icon is filled while any
account has an active window, shows `!` on error, and fades when every
scheduled account is paused; optionally it also shows the time until the
soonest window expires.

Clicking the icon opens a panel with the next tasks to fire across all
accounts — how many is configurable in **General** (1–5, default 1) —
ordered by time; paused accounts are skipped, so it only shows what will
actually run. The first is a highlight card, the rest compact rows: provider
icon, account label, event name, and time. If there's nothing to show, the
panel explains why (no active schedules, every account paused, or just
waiting for the next window/time). Clicking a card or row opens
**Settings → Tasks** filtered to that account. The footer has **Tasks**,
**History** and **Settings…**; the header shows a warning if a CLI is
missing, plus **Quit**.

**Settings** is a sidebar window with four sections:

- **Accounts** — for each account, the logged-in identity / alias, provider
  with its icon, local folder, how many active schedules target it, and
  per-account **Pause/Resume**. Add or remove accounts here
- **Tasks** — the single list of schedules. Each has a name, a type
  (Claude / Codex / shell command) with its own config, an account, and a
  repetition — **Continuous** (a 5-hour-window renewal, max one per account)
  or **Fixed times** (times × weekdays). One form creates or edits any of them;
  new schedules start with an empty command field. Jumping in from a task in
  the menu panel filters this list to that account, with a chip to clear the
  filter
- **History** — recent dispatches as cards with status, provider icon, model,
  account alias/email, command, response and error details; filterable by
  account the same way as Tasks
- **General** — Launch at Login, time remaining in the menu bar, how many
  upcoming fires the menu panel shows (1–5), Language (English or
  Portuguese), and the app version

## How it works

To manage continuous renewals, HiYashi streams the account's local transcripts
(`<account>/projects/**.jsonl` for Claude, `sessions/**.jsonl` for Codex, line
by line, ordered by `mtime`) and reconstructs the current 5-hour window. If one
is active, only a redundant continuous renewal is skipped; fixed-time schedules
always run. A Claude window starts at the top of the hour of its first message
(mirroring how the plan counts it); a Codex window starts at the exact time.

A Claude dispatch runs:

```
claude -p --model <model> --effort <effort> [--safe-mode] "<text>"
```

with `CLAUDE_CONFIG_DIR` pinned to the target account when the schedule is in
batch mode. By default, Claude/Codex open in Terminal.app without `-p` / `exec`,
using the same prompt and environment so the interactive session stays open;
a fixed-time interactive schedule opens at its scheduled time even if the
account already has an active window. When no working directory is set,
interactive sessions open in
`~/Library/Application Support/HiYashi/workspace` (never the home folder,
whose trust Claude Code only keeps per session), and HiYashi
pre-trusts the folder in the account's `.claude.json` — and pre-approves
external `CLAUDE.md` imports — so neither the "do you trust this folder?" nor
the "allow external imports?" prompt blocks the unattended session. Only one
HiYashi instance runs at a time: a second
launch shows a notice and quits (two instances would double-fire schedules).
The defaults — Haiku, low effort, `--safe-mode` (skips CLAUDE.md/skills/MCP) and
the command `1+1` — make it the cheapest possible ping that opens the window. A
batch Codex dispatch runs `codex exec [--model <model>] --sandbox read-only [-c
model_reasoning_effort=<effort>] "<text>"` with `CODEX_HOME` pinned instead,
and has its own minimal built-in `1+1` default. When you leave the Codex model
(or reasoning) unset, HiYashi omits the flag so the account's own
`config.toml` default is used — the only value guaranteed to be accepted by the
account's plan. Shell commands run through your login shell.

Which account is Claude vs. Codex is inferred from folder content, not name,
in this order: a `.claude.json` means Claude; else an `auth.json` means Codex;
else a `projects/` subfolder means Claude; else a `sessions/` subfolder means
Codex. So `auth.json` wins over `projects/` when both are present.

A **Continuous** schedule arms at the end of the detected window and chains
the next one, 24/7; a redundant renewal attempt is skipped while the account
window is still active. A **Fixed times** schedule always fires at its times ×
weekdays, in either batch or interactive mode. On wake, fixed times fire at
most once to catch up the most recent occurrence missed — a long sleep never
triggers a burst of backlogged fires, and launch itself never replays
occurrences missed before it. The old *Scheduled* renewal (daily
anchor + 0/5/10/15h) is simply a fixed-times schedule with four times after
migration.
