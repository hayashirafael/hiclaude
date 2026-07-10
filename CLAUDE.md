# HiClaude Agent Notes

## Overview

macOS menu bar app (Swift 5.9 + SwiftUI `MenuBarExtra`, macOS 13+, SPM, zero
external dependencies) that keeps Claude plan accounts with their 5-hour usage
window always open, renewing each account on its own. The app is
account-centered: there are no global schedules, no default account, no
globally-active message.

## Domain vocabulary

- **Account** — a Claude Code config directory (`~/.claude`, `~/.claude2`, …).
  Display label resolves alias → logged-in email (`oauthAccount.emailAddress`
  in `<dir>/.claude.json`) → folder name.
- **Window** — the plan's 5-hour usage block. Inferred passively by streaming
  the local transcripts at `<account>/projects/**.jsonl`; the app never calls
  the CLI or the network to detect it.
- **Renewal** — presence of an account in `AppState.renewals`
  (`[path: AccountRenewal]`; absence = Off). Two modes:
  - `automatic` — arms at the end of the detected window and chains 5h windows
    24/7 (daily anchor drifts).
  - `scheduled` — anchored to a daily start time (default 09:00,
    `AppState.defaultAnchorMinutes`). Fires at anchor + 0/5/10/15h
    (4 windows/day), leaving an emergent ~4h night gap. Post-sleep catch-up
    fires only if the missed slot's 5h window still covers now AND no detected
    window is active.
- **hi** — the dispatch that opens/renews a window.
- **Message** — the content of a hi: a Claude prompt (configurable model,
  effort, safe-mode, working dir), a Codex prompt (configurable model,
  reasoning effort, account), or a raw shell command. Default message: `1+1`
  · Haiku · low effort · safe-mode (uid `…0001`, `AppState.defaultMessage`);
  Codex has its own minimal default (`AppState.defaultCodexMessage`, uid
  `…0002`).
- **Provider** — `claude` or `codex`, the axis that differentiates account
  discovery, window detection and dispatch (`Provider.swift`). Detected by
  folder *content*, not name (`Provider.detect(at:)`): `.claude.json` →
  claude; else `auth.json` → codex; else `projects/` → claude; else
  `sessions/` → codex; else no signature (`nil`). Each provider carries its
  own transcripts subpath (`projects`/`sessions`), env var
  (`CLAUDE_CONFIG_DIR`/`CODEX_HOME`) and CLI binary name.
- **Tarefa** (`ScheduledTask`) — a command fired at fixed times × weekdays
  (`AgendaMath.swift`), independent of any account's renewal. Managed in the
  Horários section (`HorariosView.swift`) and driven by `TaskScheduler`,
  which arms one timer per enabled task and — on wake or launch — fires a
  single catch-up per task for the most recent occurrence missed since its
  last fire (never a burst of backlogged fires for a long sleep).

## Architecture map

- `AppState.swift` — central observable state, UserDefaults persistence,
  legacy migrations (`renewAccounts` → automatic renewals; raw string keys
  `"renewAccounts"`/`"lastEvent"` are intentional there).
- `AppEnvironment.swift` — composition root; wires engine ↔ controller,
  observes sleep/wake and `$renewals`.
- `RenewalEngine.swift` — per-account timers by mode, 120s dedupe,
  `pendingRetry` for dispatches discarded by the controller's `isRunning`
  guard.
- `ScheduleMath.swift` — pure functions for the scheduled cycle
  (`nextScheduledRenewal`, `missedScheduledRenewal`).
- `SessionDetector.swift` — active window end from transcripts.
- `FireController.swift` — orchestrates one dispatch: skip when a window is
  already active (Claude messages only), record to history, `isRunning` guard.
- `Provider.swift` — the claude/codex axis: folder-content detection,
  transcripts subpath, env var, CLI binary name, display name.
- `CommandRunner.swift` — subprocess: `claude -p --model … --effort …
  [--safe-mode] "<text>"`, `codex exec --model … --sandbox read-only …
  "<text>"`, or login-shell command; pins `CLAUDE_CONFIG_DIR`/`CODEX_HOME`
  per dispatch; 60s timeout.
- `AgendaMath.swift` — pure functions for the Horários cycle (fixed times ×
  weekdays): `nextOccurrence`, `lastMissedOccurrence` (single catch-up on
  wake).
- `TaskScheduler.swift` — per-task timers driven by `AgendaMath`, mirrors
  `RenewalEngine`'s pattern (120s dedupe, `pendingRetry` for dispatches
  discarded by the controller's `isRunning` guard).
- UI: `MenuContent.swift` (per-account status menu + next-task line),
  `SettingsView.swift` (sidebar: Contas · Horários · Comandos · Histórico ·
  Geral → `ContasView`, `HorariosView`, `MessagesTab`, `HistoryTab`,
  `GeneralTab`).

## Commands

```bash
swift build                     # must always compile between changes
swift test                      # full suite
swift test --filter <Class>     # focused
swift run HiClaude              # run the menu bar app locally
./scripts/make-app.sh           # build/HiClaude.app (ad-hoc signed)
./scripts/make-dmg.sh           # build/HiClaude-<version>.dmg
```

## Conventions

- UI strings and code comments in Português (Brasil) with correct accents.
- XCTest; test classes are `@MainActor` when touching `AppState`/engines.
- TDD: write the failing test first. Tests use fakes (`Clock`,
  `SessionDetecting`) — never real timers or sleeps.
- Commit prefixes: `feat:` / `fix:` / `refactor:` / `docs:` / `test:`.

## Repo hygiene

`CONTEXT.md`, `docs/` and `.superpowers/` are local working notes — never
commit them (they are gitignored). Do not add session trailers or AI-process
footers to commits or PRs in this repo.

## Release prompt

After any code, documentation, workflow, packaging, or cask change in this repo,
ask the user whether to create a new release before finishing the task.

If the answer is yes, use the existing release flow:

1. Confirm the next semantic version.
2. Update `scripts/Info.plist` if the app version changes.
3. Commit the changes with the repo-local Git identity.
4. Create and push a `vX.Y.Z` tag.
5. Verify the `release` GitHub Actions workflow finishes successfully.
6. Verify the Homebrew tap cask is updated and `brew upgrade --cask hiclaude`
   can see the new version.

Do not assume that pushing `main` updates users. Homebrew users only receive an
update after a new tag/release updates `hayashirafael/homebrew-tap`.
