# HiYashi Agent Notes

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
- **Agendamento** (`ScheduledTask`) — the single unified concept: a command
  dispatched either **continuously** or on **fixed times**. Carries an embedded
  prompt (`command: Message`), an optional name, an `enabled` toggle, and a
  `repetition`:
  - `continuous` — arms at the end of the detected window and chains 5h windows
    24/7 (the old *automatic renewal*); driven by `RenewalEngine`, keyed by the
    account the command targets. Max one continuous agendamento per account
    (`AppState.hasContinuousConflict`).
  - `fixed` — fixed times × weekdays (`AgendaMath`), driven by `TaskScheduler`,
    with a single catch-up on wake. The old *scheduled renewal* (anchor +
    0/5/10/15h) is just four fixed times after migration.
  There is no `AppState.renewals` dict and no command library any more.
- **hi** — the dispatch that opens/renews a window.
- **Message** — the embedded content of an agendamento: a Claude prompt
  (configurable model, effort, safe-mode, working dir), a Codex prompt
  (configurable model, reasoning effort, account), or a raw shell command.
  Default message: `1+1` · Haiku · low effort · safe-mode (uid `…0001`,
  `AppState.defaultMessage`); Codex has its own minimal default
  (`AppState.defaultCodexMessage`, uid `…0002`). Codex with no explicit model
  omits `--model` (and reasoning) so the account's `config.toml` default wins.
- **Provider** — `claude` or `codex`, the axis that differentiates account
  discovery, window detection and dispatch (`Provider.swift`). Detected by
  folder *content*, not name (`Provider.detect(at:)`): `.claude.json` →
  claude; else `auth.json` → codex; else `projects/` → claude; else
  `sessions/` → codex; else no signature (`nil`). Each provider carries its
  own transcripts subpath (`projects`/`sessions`), env var
  (`CLAUDE_CONFIG_DIR`/`CODEX_HOME`) and CLI binary name.
## Architecture map

- `AppState.swift` — central observable state, UserDefaults persistence,
  one-way migrations to unified agendamentos: legacy tasks get their referenced
  favorite embedded (`command`); legacy renewals become agendamentos
  (`automatic` → `continuous`, `scheduled` → four `fixed` times); the
  `renewals`/`renewAccounts`/`favorites` keys are then removed. Raw string keys
  (`"renewAccounts"`/`"lastEvent"`) are intentional there.
- `AppEnvironment.swift` — composition root; wires both engines ↔ controller,
  observes sleep/wake and `$tasks` (single `reconfigureSchedules`: continuous
  agendamentos feed `RenewalEngine`, fixed ones `TaskScheduler`).
- `RenewalEngine.swift` — accounts with a continuous agendamento; per-account
  timers armed at the detected window end, 120s dedupe, `pendingRetry` for
  dispatches discarded by the controller's `isRunning` guard.
- `SessionDetector.swift` — active window end from transcripts.
- `FireController.swift` — orchestrates one dispatch: only continuous renewal
  skips when a window is already active; fixed/manual runs always execute.
  Records to history and applies the global `isRunning` guard.
- `Provider.swift` — the claude/codex axis: folder-content detection,
  transcripts subpath, env var, CLI binary name, display name.
- `CommandRunner.swift` — subprocess: `claude -p --model … --effort …
  [--safe-mode] "<text>"`, `codex exec [--model …] --sandbox read-only …
  [-c model_reasoning_effort=…] "<text>"` (model/reasoning flags omitted when
  unset → account default), or login-shell command; pins
  `CLAUDE_CONFIG_DIR`/`CODEX_HOME` per dispatch; 60s timeout.
- `TerminalLauncher.swift` — disparo interativo (`message.resolvedRunInTerminal`):
  abre uma sessão no Terminal.app via AppleScript rodando um `.sh` temporário
  (auto-`rm`); fixa `CLAUDE_CONFIG_DIR`/`CODEX_HOME`, faz `cd` para o working dir
  (default `~/Library/Application Support/HiYashi/workspace` — nunca o home, cujo
  trust não persiste). `seedTrust` pré-grava `projects[<dir>]` no `.claude.json` da
  conta para o `claude` não-supervisionado nunca travar em prompt:
  `hasTrustDialogAccepted` + `hasClaudeMdExternalIncludesApproved`/`…WarningShown`
  (não há flag/env do CLI que auto-aprove imports externos de CLAUDE.md mantendo o
  CLAUDE.md ativo). Só Claude; Codex nunca toca no `.claude.json`.
- `AgendaMath.swift` — pure functions for the fixed cycle (times × weekdays):
  `nextOccurrence`, `lastMissedOccurrence` (single catch-up on wake), and
  `date(bySettingMinutes:ofDay:calendar:)`.
- `TaskScheduler.swift` — per-agendamento timers (fixed ones) driven by
  `AgendaMath`, mirrors `RenewalEngine`'s pattern (`pendingRetry` for
  dispatches discarded by the controller's `isRunning` guard). Dedupe is by
  fired-occurrence identity (never a wall-clock window — adjacent-minute
  occurrences must both fire); creating/editing a task advances a catch-up
  floor and never counts as a fire.
- `SingleInstanceLock.swift` — `flock` on the compatibility path
  `~/Library/Application Support/HiClaude/instance.lock`; keeping the legacy
  path prevents old HiClaude and current HiYashi builds from running together.
  A second launch
  (dev binary or packaged .app) alerts and exits before `AppEnvironment`
  exists (two instances double-fire and clobber each other's history).
- UI: `MenuContent.swift` (per-account status menu + next-task line),
  `SettingsView.swift` (sidebar: Contas · Horários · Histórico · Geral →
  `ContasView` (informative: provider/folder/active-schedule count),
  `HorariosView` (the unified agendamento list) + `AgendamentoFormSheet`,
  `HistoryTab`, `GeneralTab`).

## Commands

```bash
swift build                     # must always compile between changes
swift test                      # full suite
swift test --filter <Class>     # focused
swift run HiClaude              # run the menu bar app locally
./scripts/make-app.sh           # build/HiYashi.app (ad-hoc signed)
./scripts/make-dmg.sh           # build/HiYashi-<version>.dmg
```

## Observability

`os_log` no subsystem `dev.hiclaude` (categorias `agenda`/`fire`/`env`) marca só
decisões e mudanças de estado — em especial o descarte por `isRunning` no
`FireController` como `.error` (o "silenciador invisível"). Ao vivo:

```bash
log stream --predicate 'subsystem == "dev.hiclaude"' --level debug
```

## Conventions

- UI strings and code comments in Português (Brasil) with correct accents.
- XCTest; test classes are `@MainActor` when touching `AppState`/engines.
- TDD: write the failing test first. Tests use fakes (`Clock`,
  `SessionDetecting`) — never real timers or sleeps. Exceção:
  `AppEnvironmentTests` exercita o `AppEnvironment` real (com `FireController`/
  `TerminalLauncher` reais) via um `TaskScheduler` injetado que arma `NSTimer`
  reais, então suas datas fake DEVEM ser bem no futuro (ano 2099) — uma data de
  disparo no passado vence na hora no `RunLoop.main` e roda AppleScript de verdade
  (abre Terminal / crasha o suite).
- Commit prefixes: `feat:` / `fix:` / `refactor:` / `docs:` / `test:`.
- READMEs: `README.md` is English, `README.pt-br.md` is Portuguese (there is
  no `README.en.md`); keep them in sync and verify every behavioral claim
  against the source before writing it.
- SourceKit/LSP diagnostics go stale after files change (false "no member"
  errors); trust `swift build` / `swift test`, not the diagnostics.

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
