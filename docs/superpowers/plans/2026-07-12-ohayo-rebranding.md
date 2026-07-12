# Ohayo Rebranding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the complete current product, codebase, packaging, distribution, and documentation to Ohayo and publish the clean-break version `1.0.0`.

**Architecture:** Perform one coordinated identity cutover, starting with test-visible runtime paths and Swift package identity, then packaging and distribution, then documentation and repository metadata. Compatibility and migration code are removed; final repository and bundle scans enforce that only the Ohayo identity remains in the current tree.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Package Manager, Bash, macOS app bundles, DMG, Homebrew Cask, GitHub Actions, GitHub CLI

## Global Constraints

- Product, app, executable, package, and Swift target: `Ohayo`.
- Test target: `OhayoTests`.
- Repository: `hayashirafael/ohayo`.
- Homebrew cask: `ohayo` in `hayashirafael/tap`.
- Bundle ID and defaults domain: `io.github.hayashirafael.Ohayo`.
- Application Support directory: `~/Library/Application Support/Ohayo`.
- App and installer: `Ohayo.app` and `Ohayo-1.0.0.dmg`.
- Release version and tag: `1.0.0` and `v1.0.0`.
- No migration, fallback, alias, transitional cask, or compatibility behavior.
- Preserve the current icon artwork; rename identity-bearing asset filenames.
- Current repository content and tracked path names must contain no former product identities; Git history and existing releases are excluded.
- Keep macOS 13 as the minimum platform and add no dependencies.
- Do not create or push `v1.0.0` until all local gates pass.

## File Map

- `Package.swift`: declares the Ohayo package, executable target, resources, and test target.
- `Sources/Ohayo/OhayoApp.swift`: owns the app entry point and initializes only Ohayo paths.
- `Sources/Ohayo/AppPaths.swift`: owns the new support, workspace, and instance-lock paths without migration.
- `Sources/Ohayo/ProviderVisual.swift`: resolves the renamed SwiftPM resource bundle.
- `Sources/Ohayo/Localization.swift`, `MenuPanel.swift`, `LoginItem.swift`: own user-visible app identity.
- `Tests/OhayoTests/*`: compile against the Ohayo module and verify paths, resources, notifications, and existing behavior.
- `scripts/Info.plist`: owns bundle identity and `1.0.0` version metadata.
- `scripts/make-app.sh`: produces and signs `build/Ohayo.app`.
- `scripts/make-dmg.sh`: packages `build/Ohayo-1.0.0.dmg`.
- `scripts/update-cask.sh`: generates `Casks/ohayo.rb` for the renamed repository and artifact.
- `.github/workflows/release.yml`: tests, publishes the Ohayo DMG, and updates the Ohayo cask.
- `README.md`, `README.pt-br.md`, `CLAUDE.md`, `CONTEXT.md`, `docs/**`, `.superpowers/**`: describe only the current Ohayo identity.
- `assets/AppIcon.png`, `assets/AppIcon-Ohayo.png`: retain the current artwork under identity-safe names.

---

### Task 1: Establish the Ohayo runtime-path contract

**Files:**
- Modify: `Tests/OhayoTests/AppPathsTests.swift`
- Modify: `Sources/Ohayo/AppPaths.swift`
- Modify: `Sources/Ohayo/OhayoApp.swift`

**Interfaces:**
- Consumes: the structurally renamed paths created at the start of this task.
- Produces: `AppPaths.supportDirectory(home:)`, `AppPaths.instanceLockPath(home:)`, and `AppPaths.workspaceDirectory(home:fileManager:)`, all returning only Ohayo paths.

- [ ] **Step 1: Move the source, test, entry-point, and named-icon paths**

Discover the single current target directories instead of storing their former identity in this plan:

```bash
SOURCE_DIR="$(find Sources -mindepth 1 -maxdepth 1 -type d -print -quit)"
TEST_DIR="$(find Tests -mindepth 1 -maxdepth 1 -type d -print -quit)"
ENTRY_FILE="$(rg -l '^@main$' "$SOURCE_DIR")"
NAMED_ICON="$(find assets -maxdepth 1 -type f -name 'AppIcon-*.png' -print -quit)"
test -n "$SOURCE_DIR" && test -n "$TEST_DIR" && test -n "$ENTRY_FILE" && test -n "$NAMED_ICON"
git mv "$SOURCE_DIR" Sources/Ohayo
git mv "Sources/Ohayo/$(basename "$ENTRY_FILE")" Sources/Ohayo/OhayoApp.swift
git mv "$TEST_DIR" Tests/OhayoTests
git mv "$NAMED_ICON" assets/AppIcon-Ohayo.png
```

Expected: `git status --short` reports four rename groups and no deleted/untracked pairs.

- [ ] **Step 2: Update package identity and test imports**

Use `apply_patch` to replace `Package.swift` with:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ohayo",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Ohayo", path: "Sources/Ohayo",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "OhayoTests",
            dependencies: ["Ohayo"],
            path: "Tests/OhayoTests"
        ),
    ]
)
```

Then update test imports:

```bash
OLD_MODULE="Hi""Claude"
rg -l "@testable import ${OLD_MODULE}" Tests/OhayoTests | xargs perl -pi -e "s/\@testable import ${OLD_MODULE}/\@testable import Ohayo/g"
```

- [ ] **Step 3: Replace migration tests with the clean-break path contract**

Use `apply_patch` to replace `Tests/OhayoTests/AppPathsTests.swift` with:

```swift
import XCTest
@testable import Ohayo

final class AppPathsTests: XCTestCase {
    func testSupportWorkspaceAndLockUseOhayoDirectory() {
        let home = URL(fileURLWithPath: "/tmp/ohayo-home")
        let support = home.appendingPathComponent("Library/Application Support/Ohayo")

        XCTAssertEqual(AppPaths.supportDirectory(home: home), support)
        XCTAssertEqual(AppPaths.workspaceDirectory(home: home), support.appendingPathComponent("workspace"))
        XCTAssertEqual(AppPaths.instanceLockPath(home: home), support.appendingPathComponent("instance.lock").path)
    }
}
```

- [ ] **Step 4: Run the focused test and verify the old behavior fails**

Run: `swift test --filter AppPathsTests`

Expected: FAIL because the lock still uses the pre-cutover support directory.

- [ ] **Step 5: Replace `AppPaths` with the minimal Ohayo-only implementation**

Use `apply_patch` to make `Sources/Ohayo/AppPaths.swift` contain:

```swift
import Foundation

enum AppPaths {
    static func supportDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Ohayo")
    }

    static func instanceLockPath(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        supportDirectory(home: home).appendingPathComponent("instance.lock").path
    }

    static func workspaceDirectory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL {
        supportDirectory(home: home).appendingPathComponent("workspace")
    }
}
```

Remove the migration call from `Sources/Ohayo/OhayoApp.swift` without adding cleanup or fallback behavior. Rename its `@main` type to `OhayoApp`.

- [ ] **Step 6: Run the path test**

Run: `swift test --filter AppPathsTests`

Expected: PASS with 1 test and no migration tests present.

- [ ] **Step 7: Commit structure and clean-break paths**

```bash
git add Package.swift Sources/Ohayo Tests/OhayoTests assets/AppIcon-Ohayo.png
git commit -m "refactor: establish Ohayo package and runtime paths"
```

### Task 2: Complete the Swift module and resource identity

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/Ohayo/OhayoApp.swift`
- Modify: all `Tests/OhayoTests/*.swift`
- Modify: `Sources/Ohayo/ProviderVisual.swift`
- Modify: `Tests/OhayoTests/ProviderVisualTests.swift`

**Interfaces:**
- Consumes: existing source types and the Task 1 `AppPaths` API.
- Produces: executable module `Ohayo`, test module `OhayoTests`, entry point `OhayoApp`, and resource bundle `Ohayo_Ohayo.bundle`.

- [ ] **Step 1: Confirm Task 1 structural outputs**

Run: `test -d Sources/Ohayo && test -d Tests/OhayoTests && test -f Sources/Ohayo/OhayoApp.swift && test -f assets/AppIcon-Ohayo.png`

Expected: exit 0.

- [ ] **Step 2: Update the package manifest exactly**

Confirm `Package.swift` declares:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ohayo",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Ohayo", path: "Sources/Ohayo",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "OhayoTests",
            dependencies: ["Ohayo"],
            path: "Tests/OhayoTests"
        ),
    ]
)
```

- [ ] **Step 3: Mechanically update imports, entry point, test fixtures, and resource bundle**

Build the forbidden strings at runtime so the plan itself remains identity-clean:

```bash
OLD_MODULE="Hi""Claude"
OLD_PUBLIC="Hi""Yashi"
rg -l "@testable import ${OLD_MODULE}" Tests/OhayoTests | xargs perl -pi -e "s/\@testable import ${OLD_MODULE}/\@testable import Ohayo/g"
perl -pi -e "s/${OLD_PUBLIC}App/OhayoApp/g; s/${OLD_PUBLIC}/Ohayo/g; s/${OLD_MODULE}_${OLD_MODULE}/Ohayo_Ohayo/g; s/${OLD_MODULE}/Ohayo/g" Sources/Ohayo/OhayoApp.swift Sources/Ohayo/ProviderVisual.swift Tests/OhayoTests/ProviderVisualTests.swift
```

Then use `apply_patch` for any expected string assertions reported by:

```bash
git grep -n -i -E "${OLD_MODULE}|${OLD_PUBLIC}" -- Sources/Ohayo Tests/OhayoTests Package.swift
```

Replace product labels with `Ohayo`, lowercase temporary prefixes with `ohayo`, and resource fixture paths with `/Apps/Ohayo.app/.../Ohayo_Ohayo.bundle`.

- [ ] **Step 4: Run the full Swift suite**

Run: `swift test`

Expected: PASS; build output names the `Ohayo` and `OhayoTests` targets and all existing tests pass.

- [ ] **Step 5: Commit the Swift identity cutover**

```bash
git add Package.swift Sources/Ohayo Tests/OhayoTests assets/AppIcon-Ohayo.png
git commit -m "refactor: rename Swift package to Ohayo"
```

### Task 3: Replace remaining runtime-visible identity

**Files:**
- Modify: `Sources/Ohayo/Localization.swift`
- Modify: `Sources/Ohayo/MenuPanel.swift`
- Modify: `Sources/Ohayo/LoginItem.swift`
- Modify: `Sources/Ohayo/AppEnvironment.swift`
- Modify: `Sources/Ohayo/FireController.swift`
- Modify: `Sources/Ohayo/TaskScheduler.swift`
- Modify: `Sources/Ohayo/TerminalLauncher.swift`
- Modify: matching files under `Tests/OhayoTests/`

**Interfaces:**
- Consumes: existing localization, notification, logging, and terminal-launch interfaces.
- Produces: unchanged behavior with `Ohayo` user-visible titles, `io.github.hayashirafael.Ohayo` logging identity, and `ohayo-*` temporary/test prefixes.

- [ ] **Step 1: Update expected notification and path strings in tests first**

Use `apply_patch` to change expected app prefixes in `FireControllerTests`, temporary-directory prefixes in the test suite, and any `/Apps/...` fixture paths to `Ohayo`/`ohayo`.

- [ ] **Step 2: Run affected tests and verify red state**

Run:

```bash
swift test --filter FireControllerTests
swift test --filter TerminalLauncherTests
swift test --filter AppEnvironmentTests
```

Expected: FAIL where production strings still use the previous identity.

- [ ] **Step 3: Update production identity without changing behavior**

Use the following exact values in production files:

```swift
Logger(subsystem: "io.github.hayashirafael.Ohayo", category: "agenda")
Logger(subsystem: "io.github.hayashirafael.Ohayo", category: "env")
Logger(subsystem: "io.github.hayashirafael.Ohayo", category: "fire")
```

Set menu fallback name, alert titles, notification prefixes, and login-item log prefixes to `Ohayo`. Set terminal-script prefixes to `ohayo-terminal-`. Do not change scheduling, command, localization, or notification semantics.

- [ ] **Step 4: Run the complete suite**

Run: `swift test`

Expected: PASS with no changed test count except the two removed migration tests from Task 1.

- [ ] **Step 5: Commit visible and diagnostic identity**

```bash
git add Sources/Ohayo Tests/OhayoTests
git commit -m "refactor: apply Ohayo runtime identity"
```

### Task 4: Rename bundle metadata and build artifacts

**Files:**
- Modify: `scripts/Info.plist`
- Modify: `scripts/make-app.sh`
- Modify: `scripts/make-dmg.sh`

**Interfaces:**
- Consumes: release binary `.build/release/Ohayo` and resource bundle `.build/release/Ohayo_Ohayo.bundle`.
- Produces: signed `build/Ohayo.app` and `build/Ohayo-1.0.0.dmg`.

- [ ] **Step 1: Update bundle metadata**

Use `apply_patch` so `scripts/Info.plist` has exactly these identity values:

```xml
<key>CFBundleIdentifier</key><string>io.github.hayashirafael.Ohayo</string>
<key>CFBundleName</key><string>Ohayo</string>
<key>CFBundleDisplayName</key><string>Ohayo</string>
<key>CFBundleExecutable</key><string>Ohayo</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
```

Keep the existing package type, icon, minimum system version, accessory-app setting, and Retina setting unchanged.

- [ ] **Step 2: Update build and DMG scripts**

Use `apply_patch` so the scripts consistently use:

```bash
APP="build/Ohayo.app"
RESOURCE_BUNDLE=".build/release/Ohayo_Ohayo.bundle"
DMG="build/Ohayo-${VERSION}.dmg"
```

Copy `.build/release/Ohayo` to `Contents/MacOS/Ohayo`; verify `Contents/Resources/Ohayo_Ohayo.bundle`; set DMG volume, icon item, and hidden-extension item to `Ohayo`/`Ohayo.app`.

- [ ] **Step 3: Build and verify the app bundle**

Run:

```bash
./scripts/make-app.sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/Ohayo.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' build/Ohayo.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Ohayo.app/Contents/Info.plist
test -x build/Ohayo.app/Contents/MacOS/Ohayo
test -d build/Ohayo.app/Contents/Resources/Ohayo_Ohayo.bundle
codesign --verify --deep --strict build/Ohayo.app
```

Expected output values: `io.github.hayashirafael.Ohayo`, `Ohayo`, `1.0.0`; all `test` and `codesign` commands exit 0.

- [ ] **Step 4: Generate and inspect the DMG**

Run:

```bash
./scripts/make-dmg.sh
test -f build/Ohayo-1.0.0.dmg
hdiutil imageinfo build/Ohayo-1.0.0.dmg | rg 'Ohayo'
```

Expected: DMG exists and `hdiutil imageinfo` reports the Ohayo volume metadata.

- [ ] **Step 5: Commit packaging identity**

```bash
git add scripts/Info.plist scripts/make-app.sh scripts/make-dmg.sh
git commit -m "build: package Ohayo 1.0.0"
```

### Task 5: Update Homebrew generation and release automation

**Files:**
- Modify: `scripts/update-cask.sh`
- Modify: `.github/workflows/release.yml`
- Generated for validation only: `/tmp/ohayo-cask/Casks/ohayo.rb`

**Interfaces:**
- Consumes: version `1.0.0`, `build/Ohayo-1.0.0.dmg`, and GitHub repository `hayashirafael/ohayo`.
- Produces: reproducible `Casks/ohayo.rb` and a release workflow that uploads the Ohayo DMG and updates only the Ohayo cask.

- [ ] **Step 1: Update the cask generator**

Use `apply_patch` so the generated cask contains:

```ruby
cask "ohayo" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/hayashirafael/ohayo/releases/download/v#{version}/Ohayo-#{version}.dmg"
  name "Ohayo"
  desc "Menu bar scheduler for Claude and Codex usage windows and commands"
  homepage "https://github.com/hayashirafael/ohayo"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura
  app "Ohayo.app"
  zap trash: "~/Library/Preferences/io.github.hayashirafael.Ohayo.plist"
end
```

Retain the current ad-hoc-signing caveat, changing its app name and quarantine path to Ohayo. Set `CASK="$OUT_DIR/ohayo.rb"`.

- [ ] **Step 2: Generate and audit the cask locally**

Run:

```bash
rm -rf /tmp/ohayo-cask
mkdir -p /tmp/ohayo-cask/Casks
./scripts/update-cask.sh 1.0.0 build/Ohayo-1.0.0.dmg /tmp/ohayo-cask/Casks
ruby -c /tmp/ohayo-cask/Casks/ohayo.rb
rg -n 'ohayo|Ohayo|io.github.hayashirafael.Ohayo' /tmp/ohayo-cask/Casks/ohayo.rb
```

Expected: `Syntax OK`; output includes cask token, repository URL, app, and zap domain.

- [ ] **Step 3: Update the release workflow**

Use `apply_patch` so `.github/workflows/release.yml`:

- uploads `build/Ohayo-*.dmg`;
- calls `./scripts/update-cask.sh "$VERSION" "build/Ohayo-${VERSION}.dmg" "homebrew-tap/Casks"`;
- stages `Casks/ohayo.rb`;
- commits with `Update Ohayo cask to ${GITHUB_REF_NAME}`.

Do not add a compatibility cask or alias. Removal of the pre-cutover cask is the one-time external operation in Task 8.

- [ ] **Step 4: Validate workflow syntax and references**

Run:

```bash
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); puts "YAML OK"'
rg -n 'Ohayo|ohayo' .github/workflows/release.yml scripts/update-cask.sh
```

Expected: `YAML OK` and all artifact/cask references point to Ohayo.

- [ ] **Step 5: Commit distribution automation**

```bash
git add scripts/update-cask.sh .github/workflows/release.yml
git commit -m "ci: publish Ohayo through Homebrew"
```

### Task 6: Rewrite current documentation and repository guidance

**Files:**
- Modify: `README.md`
- Modify: `README.pt-br.md`
- Modify: `CLAUDE.md`
- Modify if present: `CONTEXT.md`
- Modify: `docs/**/*.md`
- Modify: `.superpowers/**/*.md`

**Interfaces:**
- Consumes: the final identity, paths, install commands, and artifact names from Tasks 1-5.
- Produces: English and Portuguese user documentation plus internal guidance containing only the Ohayo identity.

- [ ] **Step 1: Update the two user-facing READMEs**

Use `apply_patch` to make every product mention `Ohayo`, and set installation/source commands to:

```bash
brew tap hayashirafael/tap
brew trust --cask hayashirafael/tap/ohayo
brew install --cask ohayo

git clone https://github.com/hayashirafael/ohayo.git
cd ohayo
swift test
./scripts/make-app.sh
./scripts/make-dmg.sh
open build/Ohayo.app
```

Document `Ohayo-<version>.dmg`, `/Applications/Ohayo.app`, and `~/Library/Application Support/Ohayo/workspace`. Add a clean-install note that the previous app must be fully removed before installing Ohayo, without embedding former identity strings in the repository.

- [ ] **Step 2: Rewrite internal and historical documents**

For `CLAUDE.md`, `CONTEXT.md` when present, tracked `docs/**/*.md`, and tracked `.superpowers/**/*.md`, use `apply_patch` to:

- replace the product identity with Ohayo;
- replace package, path, app, DMG, cask, repository, bundle, and defaults examples with the exact Global Constraints values;
- rewrite rebranding-history prose in present-tense Ohayo architecture terms;
- preserve technical decisions unrelated to naming;
- remove migration instructions and compatibility claims.

Do not edit Git history, old tags, or release notes already published on GitHub.

- [ ] **Step 3: Rename identity-bearing current document paths**

Run a path audit using composed strings:

```bash
OLD_A="Hi""Claude"
OLD_B="Hi""Yashi"
find . -path ./.git -prune -o -path ./.build -prune -o -path ./build -prune -o -type f -print | rg -i "${OLD_A}|${OLD_B}" || true
```

For every current-branch path reported, use `git mv <reported-path> <same-purpose-Ohayo-path>`. Do not modify or delete separate worktrees listed by `git worktree list`.

- [ ] **Step 4: Audit rendered documentation references**

Run:

```bash
rg -n 'hayashirafael/ohayo|brew install --cask ohayo|Ohayo.app|Application Support/Ohayo' README.md README.pt-br.md CLAUDE.md docs .superpowers
git diff --check
```

Expected: both READMEs contain repository, cask, app, and support-path references; `git diff --check` exits 0.

- [ ] **Step 5: Commit documentation**

```bash
git add README.md README.pt-br.md CLAUDE.md
git add -f CONTEXT.md docs .superpowers 2>/dev/null || true
git commit -m "docs: rename project documentation to Ohayo"
```

### Task 7: Enforce zero former identities and perform local release verification

**Files:**
- Modify: any current-branch file or tracked path reported by the audits.
- Verify: `Package.swift`, `Sources/Ohayo/**`, `Tests/OhayoTests/**`, `scripts/**`, `.github/**`, `README*`, `CLAUDE.md`, `CONTEXT.md`, `docs/**`, `.superpowers/**`, `assets/**`.

**Interfaces:**
- Consumes: all local deliverables from Tasks 1-6.
- Produces: a locally release-ready, identity-clean commit on `main`.

- [ ] **Step 1: Scan tracked contents and tracked path names**

Run:

```bash
OLD_A="Hi""Claude"; OLD_B="Hi""Yashi"; OLD_C="hi""claude"; OLD_D="hi""yashi"
PATTERN="${OLD_A}|${OLD_B}|${OLD_C}|${OLD_D}|dev\.${OLD_C}"
git grep -I -i -n -E "$PATTERN" -- .
git ls-files | rg -i "$PATTERN"
```

Expected: both commands exit 1 with no matches, including this plan and the approved design spec.

- [ ] **Step 2: Fix every reported content or path match**

Use `apply_patch` for content and `git mv` for tracked paths. Repeat Step 1 until both scans return no output. Do not weaken or expand exclusions.

- [ ] **Step 3: Run the complete local release gate**

Run:

```bash
swift test
./scripts/make-app.sh
codesign --verify --deep --strict build/Ohayo.app
./scripts/make-dmg.sh
test -f build/Ohayo-1.0.0.dmg
```

Expected: all tests pass, app and DMG are generated, and signature verification exits 0.

- [ ] **Step 4: Smoke-test the packaged app**

Run:

```bash
pkill -x Ohayo 2>/dev/null || true
open build/Ohayo.app
sleep 2
ps aux | rg '[O]hayo.app/Contents/MacOS/Ohayo'
defaults read io.github.hayashirafael.Ohayo >/dev/null
```

Expected: process output points to `build/Ohayo.app/Contents/MacOS/Ohayo`; defaults command exits 0 after first launch. Quit the app normally after verification.

- [ ] **Step 5: Verify diff hygiene and commit any audit fixes**

Run:

```bash
git diff --check
git status --short
```

If audit fixes exist:

```bash
git add -A
git commit -m "chore: complete Ohayo identity cleanup"
```

Expected: `git status --short` is empty after the commit.

### Task 8: Rename GitHub, cut over Homebrew, and publish `v1.0.0`

**Files:**
- External rename: current GitHub repository to `hayashirafael/ohayo`.
- External modify: `hayashirafael/homebrew-tap/Casks/ohayo.rb`.
- External delete: the pre-cutover cask file in `hayashirafael/homebrew-tap`.
- Local modify: Git remote URL only.

**Interfaces:**
- Consumes: clean `main`, passing Task 7 gates, generated cask, authenticated `gh`, and push access to both repositories.
- Produces: renamed GitHub repository, updated tap, tag `v1.0.0`, release, and installable `ohayo` cask.

- [ ] **Step 1: Re-run preflight before external mutation**

Run:

```bash
test -z "$(git status --porcelain)"
swift test
codesign --verify --deep --strict build/Ohayo.app
test -f build/Ohayo-1.0.0.dmg
gh auth status
CURRENT_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
test "$CURRENT_REPO" != "hayashirafael/ohayo"
```

Expected: all checks exit 0 and `CURRENT_REPO` identifies the repository before cutover.

- [ ] **Step 2: Rename the existing repository and update the local remote**

Run:

```bash
gh repo rename ohayo --repo "$CURRENT_REPO" --yes
git remote set-url origin https://hayashirafael@github.com/hayashirafael/ohayo.git
git remote -v
gh repo view hayashirafael/ohayo --json nameWithOwner,url -q '.nameWithOwner + " " + .url'
```

Expected: fetch/push remotes and GitHub output identify `hayashirafael/ohayo`.

- [ ] **Step 3: Push `main` to the renamed repository**

Run:

```bash
git push origin main
git ls-remote --heads origin main
```

Expected: push succeeds and `refs/heads/main` resolves remotely.

- [ ] **Step 4: Replace the Homebrew cask in one tap commit**

Run:

```bash
rm -rf /tmp/ohayo-homebrew-tap
gh repo clone hayashirafael/homebrew-tap /tmp/ohayo-homebrew-tap
./scripts/update-cask.sh 1.0.0 build/Ohayo-1.0.0.dmg /tmp/ohayo-homebrew-tap/Casks
PREVIOUS_CASK="$(git -C /tmp/ohayo-homebrew-tap ls-files 'Casks/*.rb' | while read -r f; do rg -q 'Menu bar scheduler for Claude and Codex usage windows and commands' "/tmp/ohayo-homebrew-tap/$f" && printf '%s\n' "$f"; done | rg -v '^Casks/ohayo\.rb$')"
test -n "$PREVIOUS_CASK"
git -C /tmp/ohayo-homebrew-tap rm "$PREVIOUS_CASK"
git -C /tmp/ohayo-homebrew-tap add Casks/ohayo.rb
git -C /tmp/ohayo-homebrew-tap diff --cached --check
git -C /tmp/ohayo-homebrew-tap commit -m "Replace app cask with Ohayo 1.0.0"
git -C /tmp/ohayo-homebrew-tap push origin main
```

Expected: one commit deletes the matching pre-cutover cask and creates `Casks/ohayo.rb`; push succeeds. If zero or multiple previous casks match, stop and inspect instead of deleting.

- [ ] **Step 5: Create and push the release tag**

Run:

```bash
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist)" = "1.0.0"
git tag -a v1.0.0 -m "Ohayo 1.0.0"
git push origin v1.0.0
```

Expected: tag push starts the release workflow.

- [ ] **Step 6: Verify the workflow and release artifact**

Run:

```bash
gh run list --workflow release.yml --limit 1
gh run watch "$(gh run list --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status
gh release view v1.0.0 --repo hayashirafael/ohayo
gh release download v1.0.0 --repo hayashirafael/ohayo --pattern 'Ohayo-1.0.0.dmg' --dir /tmp/ohayo-release
shasum -a 256 /tmp/ohayo-release/Ohayo-1.0.0.dmg
```

Expected: workflow succeeds, release exists, and the expected DMG downloads.

- [ ] **Step 7: Validate a clean Homebrew installation**

After the known existing installation has been removed by its user, run:

```bash
brew update
brew tap hayashirafael/tap
brew trust --cask hayashirafael/tap/ohayo
brew install --cask ohayo
test -d /Applications/Ohayo.app
open /Applications/Ohayo.app
ps aux | rg '[/]Applications/Ohayo.app/Contents/MacOS/Ohayo'
```

Expected: Homebrew installs `Ohayo.app` and the process runs from `/Applications/Ohayo.app`.

- [ ] **Step 8: Record final release evidence**

Add a short release-verification section to `docs/superpowers/plans/2026-07-12-ohayo-rebranding.md` containing the successful workflow URL, release URL, installed app path, and SHA-256 from Step 6. Then run:

```bash
git add -f docs/superpowers/plans/2026-07-12-ohayo-rebranding.md
git commit -m "docs: record Ohayo 1.0.0 release verification"
git push origin main
```

Expected: the final evidence commit is present on `main` and `git status --short` is empty.
