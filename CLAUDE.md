# Ohayo Agent Notes

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
    24/7; driven by `RenewalEngine`, keyed by the account the command targets.
    Max one continuous agendamento per account (`AppState.hasContinuousConflict`).
  - `fixed` — fixed times × weekdays (`AgendaMath`), driven by `TaskScheduler`,
    with a single catch-up on wake.
  There is no `AppState.renewals` dict and no command library any more.
- **hi** — the dispatch that opens/renews a window.
- **Message** — the embedded content of an agendamento: a Claude prompt
  (configurable model, effort, safe-mode, working dir), a Codex prompt
  (configurable model, reasoning effort, account), or a raw shell command.
  Default message: `1+1` · Haiku · low effort · safe-mode (uid `…0001`,
  `AppState.defaultMessage`); Codex has its own minimal default
  (`AppState.defaultCodexMessage`, uid `…0002`). Codex with no explicit model
  omits `--model` (and reasoning) so the account's `config.toml` default wins.
  A Message can carry an optional account skill (`skill: String?`), detected by
  `SkillCatalog` (personal + plugin skills for Claude, `skills/` only for
  Codex) and prefixed at dispatch via `resolvedPromptText` (`/skill …` for
  Claude, `$skill …` for Codex); with a skill present, `resolvedSafeMode` is
  `false` because safe-mode would skip the skill.
- **Provider** — `claude` or `codex`, the axis that differentiates account
  discovery, window detection and dispatch (`Provider.swift`). Detected by
  folder *content*, not name (`Provider.detect(at:)`): `.claude.json` →
  claude; else `auth.json` → codex; else `projects/` → claude; else
  `sessions/` → codex; else no signature (`nil`). Each provider carries its
  own transcripts subpath (`projects`/`sessions`), env var
  (`CLAUDE_CONFIG_DIR`/`CODEX_HOME`) and CLI binary name.
## Architecture map

- `AppState.swift` — central observable state and UserDefaults persistence for
  unified agendamentos. Pause is per account: `pausedAccounts: Set<String>`
  (standardized paths, persisted). `windowEnds: [URL: Date]` (not persisted)
  holds the detected 5h-window end per scheduled account, published by
  `AppEnvironment.refreshWindowEnds()`. `accountFilter: URL?` is the deep-link
  the menu panel sets to scope the Tasks/History tabs to one account
  (`taskMatchesFilter`/`matchesFilter`), with a clear-filter chip in both.
- `AppEnvironment.swift` — composition root; wires both engines ↔ controller,
  observes sleep/wake and `$tasks` (single `reconfigureSchedules`: continuous
  agendamentos feed `RenewalEngine`, fixed ones `TaskScheduler`).
  `refreshWindowEnds()` queries the `SessionDetector` for every scheduled
  account and publishes `AppState.windowEnds`; called when the menu panel
  opens, no timer of its own.
- `RenewalEngine.swift` — accounts with a continuous agendamento; per-account
  timers armed at the detected window end, 120s dedupe, `pendingRetry` for
  dispatches discarded by the controller's `isRunning` guard.
- `SessionDetector.swift` — active window end from transcripts.
- `FireController.swift` — orchestrates one dispatch: only continuous renewal
  skips when a window is already active; fixed/manual runs always execute.
  Records to history and applies the global `isRunning` guard. A paused
  account (`AppState.isPaused`) silently discards Claude/Codex dispatches
  (shell commands still run) without recording history; returns `true` so
  engines don't retry via `pendingRetry` — resuming only picks up the next
  scheduled event, never a catch-up for what was skipped while paused.
- `Provider.swift` — the claude/codex axis: folder-content detection,
  transcripts subpath, env var, CLI binary name, display name.
- `CommandRunner.swift` — subprocess: `claude -p --model … --effort …
  [--safe-mode] "<prompt>"`, `codex exec [--model …] --sandbox read-only …
  [-c model_reasoning_effort=…] "<prompt>"` (model/reasoning flags omitted when
  unset → account default), or login-shell command; pins
  `CLAUDE_CONFIG_DIR`/`CODEX_HOME` per dispatch; 60s timeout; the prompt comes
  from `resolvedPromptText` (skill prefixed when present).
- `TerminalLauncher.swift` — disparo interativo (`message.resolvedRunInTerminal`):
  abre uma sessão no Terminal.app via AppleScript rodando um `.sh` temporário
  (auto-`rm`); fixa `CLAUDE_CONFIG_DIR`/`CODEX_HOME`, faz `cd` para o working dir
  (default `~/Library/Application Support/Ohayo/workspace` — nunca o home, cujo
  trust não persiste). `seedTrust` pré-grava `projects[<dir>]` no `.claude.json` da
  conta para o `claude` não-supervisionado nunca travar em prompt:
  `hasTrustDialogAccepted` + `hasClaudeMdExternalIncludesApproved`/`…WarningShown`
  (não há flag/env do CLI que auto-aprove imports externos de CLAUDE.md mantendo o
  CLAUDE.md ativo). Usa o mesmo `resolvedPromptText` do batch; só Claude toca no
  `.claude.json`, Codex nunca.
- `AgendaMath.swift` — pure functions for the fixed cycle (times × weekdays):
  `nextOccurrence`, `lastMissedOccurrence` (single catch-up on wake), and
  `date(bySettingMinutes:ofDay:calendar:)`.
- `TaskScheduler.swift` — per-agendamento timers (fixed ones) driven by
  `AgendaMath`, mirrors `RenewalEngine`'s pattern (`pendingRetry` for
  dispatches discarded by the controller's `isRunning` guard). Dedupe is by
  fired-occurrence identity (never a wall-clock window — adjacent-minute
  occurrences must both fire); creating/editing a task advances a catch-up
  floor and never counts as a fire.
- `SingleInstanceLock.swift` — `flock` on
  `~/Library/Application Support/Ohayo/instance.lock`. A second launch
  (dev binary or packaged .app) alerts and exits before `AppEnvironment`
  exists, avoiding duplicate schedules and history clobbering.
- UI: `MenuBarLabel.swift` (just the bar glyph — filled while any account has
  an active window, `!` on error, faded when every scheduled account is
  paused; optional remaining-time text) + `MenuPanel.swift` (the
  `MenuBarExtra` content, `.menuBarExtraStyle(.window)`: the next N tasks to
  fire across all accounts, N = `AppState.panelUpcomingCount` (1–5, default 1,
  a stepper in Ajustes › Geral), ordered by time — paused accounts are
  skipped, so the panel only shows what will actually run. The first event is
  a highlight card, the rest compact rows; each shows provider icon · account
  label · event name · time. Empty states: `noActiveSchedules` /
  `allAccountsPaused` / `waitingForWindow`. Clicking a card/row opens
  Settings › Tasks filtered to that account (the `accountFilter` deep-link);
  no per-account hover actions, no 5h-window remaining, no status dot anymore.
  Plus a header (missing-CLI warning, Quit) + footer (Tasks · History ·
  Settings); pure logic (`upcomingEvents`, `emptyState`, `eventName`, and the
  retained `scheduledAccounts` — which still feeds
  `AppEnvironment.refreshWindowEnds` for the bar glyph; `nextEvent` was
  removed) lives in `MenuPanelLogic.swift`, testable without UI. Replaces the
  old native menu (`MenuContent.swift`). `SettingsView.swift`
  (sidebar: Contas · Tarefas · Histórico · Geral — the `horarios`
  case/rawValue is unchanged for persistence, only its displayed title
  changed from "Horários" to "Tarefas"/"Tasks") →
  `ContasView` (per-account pause/resume now lives here, alongside
  provider/folder/active-schedule count),
  `HorariosView` (unified agendamento list: fixed header bar with summary ·
  filters (account/provider/status/type) · sort · new-task button; compact
  rows expand on click; per-row manual "run now" via
  `AppEnvironment.fireNow`, origin `.manual`; list logic in the pure
  `HorariosListModel`; also scoped by the menu panel's `AppState.accountFilter`
  deep-link, with a clear-filter chip) + `AgendamentoFormSheet`
  (fixed times as chips via `TimeChipsEditor`, 5h chain generator, day
  presets, next-fire preview), `HistoryTab` (also filterable by
  `accountFilter`), `GeneralTab`).

## Commands

```bash
swift build                     # must always compile between changes
swift test                      # full suite
swift test --filter <Class>     # focused
swift run Ohayo                 # run the menu bar app locally
./scripts/make-app.sh           # build/Ohayo.app (ad-hoc signed)
./scripts/make-dmg.sh           # build/Ohayo-<version>.dmg
```

## Observability

`os_log` no subsystem `io.github.hayashirafael.Ohayo` (categorias `agenda`/`fire`/`env`) marca só
decisões e mudanças de estado — em especial o descarte por `isRunning` no
`FireController` como `.error` (o "silenciador invisível"). Ao vivo:

```bash
log stream --predicate 'subsystem == "io.github.hayashirafael.Ohayo"' --level debug
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
6. Verify the Homebrew tap cask is updated and `brew upgrade --cask ohayo`
   can see the new version.

Do not assume that pushing `main` updates users. Homebrew users only receive an
update after a new tag/release updates `hayashirafael/homebrew-tap`.
