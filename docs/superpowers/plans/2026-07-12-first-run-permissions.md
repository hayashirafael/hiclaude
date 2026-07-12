# First-Run Permissions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a non-blocking first-run guide that lets users explicitly configure notifications, test Terminal automation, and optionally enable launch at login.

**Architecture:** Persist only whether the initial guide was dismissed in `AppState`, while dedicated injectable clients always read the live macOS integration states. A small startup view opens an independent SwiftUI window once for bundled first runs; a view model coordinates actions without invoking system prompts during initialization.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, UserNotifications, ServiceManagement, NSAppleScript, XCTest, macOS 13+

## Global Constraints

- The guide must never block access to the menu, settings, or existing features.
- A macOS authorization prompt may appear only after an explicit user action or direct use of the corresponding feature.
- Closing the guide and selecting `Configure Later` both dismiss automatic presentation without marking integrations as allowed.
- The guide must remain manually reopenable from General settings.
- Launch at login is optional and disabled by default.
- Do not request Accessibility, Screen Recording, Calendar, Files, or any permission the app does not currently use.
- Keep all visible copy available in English and Portuguese through the existing `L10n` type.
- Preserve macOS 13.0 as the deployment floor and add no package dependency.

---

## File Structure

- Create `Sources/Ohayo/PermissionSetup.swift`: shared statuses, injectable clients, production adapters, and the `PermissionSetupModel` coordinator.
- Create `Sources/Ohayo/PermissionSetupView.swift`: first-run window UI and per-item rows.
- Create `Sources/Ohayo/StartupCoordinatorView.swift`: bundled-first-run opening decision.
- Create `Tests/OhayoTests/PermissionSetupTests.swift`: client mapping and model behavior.
- Create `Tests/OhayoTests/StartupCoordinatorTests.swift`: persisted opening decision.
- Modify `Sources/Ohayo/AppState.swift`: persist dismissal of automatic setup.
- Modify `Sources/Ohayo/SystemNotifier.swift`: deliver only when already authorized; never prompt from notification delivery.
- Modify `Sources/Ohayo/LoginItem.swift`: expose an injectable login-item adapter while preserving existing behavior.
- Modify `Sources/Ohayo/OhayoApp.swift`: register the guide window and startup coordinator.
- Modify `Sources/Ohayo/GeneralTab.swift`: add the manual reopen action.
- Modify `Sources/Ohayo/Localization.swift`: add English and Portuguese setup copy.
- Modify `scripts/Info.plist`: declare the Terminal Apple Events purpose.
- Modify `README.md` and `README.pt-br.md`: document first-run setup and recovery after denial.

---

### Task 1: Persist the first-run dismissal decision

**Files:**
- Modify: `Sources/Ohayo/AppState.swift`
- Test: `Tests/OhayoTests/AppStateTests.swift`
- Create: `Tests/OhayoTests/StartupCoordinatorTests.swift`
- Create: `Sources/Ohayo/StartupCoordinatorView.swift`

**Interfaces:**
- Produces: `AppState.hasDismissedPermissionGuide: Bool`
- Produces: `AppState.dismissPermissionGuide()`
- Produces: `StartupCoordinator.shouldOpenGuide(hasDismissed:isBundled:) -> Bool`
- Consumes: an injected `UserDefaults` suite and the current bundle-validity signal.

- [ ] **Step 1: Write failing persistence tests**

Append to `Tests/OhayoTests/AppStateTests.swift`:

```swift
func testPermissionGuideStartsUndismissed() {
    let state = AppState(defaults: freshDefaults())
    XCTAssertFalse(state.hasDismissedPermissionGuide)
}

func testPermissionGuideDismissalPersists() {
    let defaults = freshDefaults()
    let state = AppState(defaults: defaults)

    state.dismissPermissionGuide()

    XCTAssertTrue(state.hasDismissedPermissionGuide)
    XCTAssertTrue(AppState(defaults: defaults).hasDismissedPermissionGuide)
}
```

- [ ] **Step 2: Run the persistence tests and verify RED**

Run:

```bash
swift test --filter AppStateTests.testPermissionGuide
```

Expected: compilation fails because `hasDismissedPermissionGuide` and `dismissPermissionGuide()` do not exist.

- [ ] **Step 3: Implement minimal persisted state**

Add to `AppState.Keys`:

```swift
static let hasDismissedPermissionGuide = "hasDismissedPermissionGuide"
```

Add a stored property near the other user preferences:

```swift
@Published private(set) var hasDismissedPermissionGuide: Bool

func dismissPermissionGuide() {
    hasDismissedPermissionGuide = true
    defaults.set(true, forKey: Keys.hasDismissedPermissionGuide)
}
```

Initialize it before the end of `AppState.init`:

```swift
self.hasDismissedPermissionGuide = defaults.bool(forKey: Keys.hasDismissedPermissionGuide)
```

- [ ] **Step 4: Run persistence tests and verify GREEN**

Run:

```bash
swift test --filter AppStateTests.testPermissionGuide
```

Expected: both tests pass.

- [ ] **Step 5: Write failing startup-decision tests**

Create `Tests/OhayoTests/StartupCoordinatorTests.swift`:

```swift
import XCTest
@testable import Ohayo

final class StartupCoordinatorTests: XCTestCase {
    func testBundledFirstRunOpensGuide() {
        XCTAssertTrue(StartupCoordinator.shouldOpenGuide(
            hasDismissed: false, isBundled: true))
    }

    func testDismissedGuideDoesNotOpenAutomatically() {
        XCTAssertFalse(StartupCoordinator.shouldOpenGuide(
            hasDismissed: true, isBundled: true))
    }

    func testUnbundledDevelopmentRunDoesNotOpenGuide() {
        XCTAssertFalse(StartupCoordinator.shouldOpenGuide(
            hasDismissed: false, isBundled: false))
    }
}
```

- [ ] **Step 6: Run startup tests and verify RED**

Run:

```bash
swift test --filter StartupCoordinatorTests
```

Expected: compilation fails because `StartupCoordinator` does not exist.

- [ ] **Step 7: Implement the startup decision and opening view**

Create `Sources/Ohayo/StartupCoordinatorView.swift`:

```swift
import SwiftUI

enum StartupCoordinator {
    static func shouldOpenGuide(hasDismissed: Bool, isBundled: Bool) -> Bool {
        isBundled && !hasDismissed
    }
}

struct StartupCoordinatorView: View {
    @ObservedObject var state: AppState
    let isBundled: Bool
    @Environment(\.openWindow) private var openWindow
    @State private var evaluated = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                guard !evaluated else { return }
                evaluated = true
                if StartupCoordinator.shouldOpenGuide(
                    hasDismissed: state.hasDismissedPermissionGuide,
                    isBundled: isBundled
                ) {
                    openWindow(id: "permissions")
                }
            }
    }
}
```

- [ ] **Step 8: Run focused tests and commit**

Run:

```bash
swift test --filter StartupCoordinatorTests
swift test --filter AppStateTests.testPermissionGuide
```

Expected: all selected tests pass.

Commit:

```bash
git add Sources/Ohayo/AppState.swift Sources/Ohayo/StartupCoordinatorView.swift Tests/OhayoTests/AppStateTests.swift Tests/OhayoTests/StartupCoordinatorTests.swift
git commit -m "feat: persist first-run permission guide state"
```

---

### Task 2: Separate notification authorization from delivery

**Files:**
- Create: `Sources/Ohayo/PermissionSetup.swift`
- Create: `Tests/OhayoTests/PermissionSetupTests.swift`
- Modify: `Sources/Ohayo/SystemNotifier.swift`

**Interfaces:**
- Produces: `PermissionAccessStatus` with `.notConfigured`, `.allowed`, `.denied`, and `.failed(String)`.
- Produces: `NotificationPermissionClient` with `status()` and `request()` async methods.
- Produces: `SystemNotificationPermissionClient` backed by `UNUserNotificationCenter`.
- Consumes: the same authorization-state mapping in the setup model and `SystemNotifier`.

- [ ] **Step 1: Write failing notification mapping tests**

Create `Tests/OhayoTests/PermissionSetupTests.swift`:

```swift
import UserNotifications
import XCTest
@testable import Ohayo

final class PermissionSetupTests: XCTestCase {
    func testNotificationAuthorizationMapping() {
        XCTAssertEqual(SystemNotificationPermissionClient.map(.notDetermined), .notConfigured)
        XCTAssertEqual(SystemNotificationPermissionClient.map(.denied), .denied)
        XCTAssertEqual(SystemNotificationPermissionClient.map(.authorized), .allowed)
        XCTAssertEqual(SystemNotificationPermissionClient.map(.provisional), .allowed)
        XCTAssertEqual(SystemNotificationPermissionClient.map(.ephemeral), .allowed)
    }
}
```

- [ ] **Step 2: Run the mapping test and verify RED**

Run:

```bash
swift test --filter PermissionSetupTests.testNotificationAuthorizationMapping
```

Expected: compilation fails because the permission types do not exist.

- [ ] **Step 3: Define the notification client and mapping**

Create `Sources/Ohayo/PermissionSetup.swift` with:

```swift
import Foundation
import ServiceManagement
import UserNotifications

enum PermissionAccessStatus: Equatable {
    case notConfigured
    case allowed
    case denied
    case failed(String)
}

protocol NotificationPermissionClient {
    func status() async -> PermissionAccessStatus
    func request() async -> PermissionAccessStatus
}

struct SystemNotificationPermissionClient: NotificationPermissionClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func status() async -> PermissionAccessStatus {
        let settings = await center.notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    func request() async -> PermissionAccessStatus {
        do {
            _ = try await center.requestAuthorization(options: [.alert])
            return await status()
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func map(_ status: UNAuthorizationStatus) -> PermissionAccessStatus {
        switch status {
        case .notDetermined: return .notConfigured
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .allowed
        @unknown default: return .failed("unknown notification authorization status")
        }
    }
}
```

- [ ] **Step 4: Run the mapping test and verify GREEN**

Run:

```bash
swift test --filter PermissionSetupTests.testNotificationAuthorizationMapping
```

Expected: the test passes.

- [ ] **Step 5: Write a failing test proving delivery never requests permission**

Extend `PermissionSetupTests.swift` with a delivery-policy test:

```swift
func testNotificationDeliveryPolicyOnlyAllowsAuthorizedStates() {
    XCTAssertTrue(SystemNotifier.canDeliver(authorizationStatus: .authorized))
    XCTAssertTrue(SystemNotifier.canDeliver(authorizationStatus: .provisional))
    XCTAssertFalse(SystemNotifier.canDeliver(authorizationStatus: .notDetermined))
    XCTAssertFalse(SystemNotifier.canDeliver(authorizationStatus: .denied))
}
```

- [ ] **Step 6: Run the delivery-policy test and verify RED**

Run:

```bash
swift test --filter PermissionSetupTests.testNotificationDeliveryPolicy
```

Expected: compilation fails because `SystemNotifier.canDeliver` does not exist.

- [ ] **Step 7: Change delivery to query without prompting**

In `SystemNotifier`, replace the `requestAuthorization` block with:

```swift
center.getNotificationSettings { settings in
    guard Self.canDeliver(authorizationStatus: settings.authorizationStatus) else { return }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    center.add(UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil
    ))
}
```

Add:

```swift
static func canDeliver(authorizationStatus: UNAuthorizationStatus) -> Bool {
    switch authorizationStatus {
    case .authorized, .provisional, .ephemeral: return true
    case .notDetermined, .denied: return false
    @unknown default: return false
    }
}
```

- [ ] **Step 8: Run focused tests and commit**

Run:

```bash
swift test --filter PermissionSetupTests
```

Expected: all notification tests pass and no test invokes a real system prompt.

Commit:

```bash
git add Sources/Ohayo/PermissionSetup.swift Sources/Ohayo/SystemNotifier.swift Tests/OhayoTests/PermissionSetupTests.swift
git commit -m "feat: separate notification permission from delivery"
```

---

### Task 3: Add testable Terminal automation and login-item clients

**Files:**
- Modify: `Sources/Ohayo/PermissionSetup.swift`
- Modify: `Sources/Ohayo/LoginItem.swift`
- Modify: `Tests/OhayoTests/PermissionSetupTests.swift`
- Modify: `scripts/Info.plist`

**Interfaces:**
- Produces: `TerminalAutomationClient.test() async -> PermissionAccessStatus`.
- Produces: `SystemTerminalAutomationClient` with an injectable AppleScript runner.
- Produces: `LoginItemManaging` with `isSupported`, `isEnabled`, and `setEnabled(_:)`.
- Produces: `SystemLoginItemManager`, used by both General settings and the guide.

- [ ] **Step 1: Write failing Terminal automation tests**

Append to `PermissionSetupTests.swift`:

```swift
func testTerminalAutomationSuccessIsAllowed() async {
    let client = SystemTerminalAutomationClient { _ in .success(()) }
    XCTAssertEqual(await client.test(), .allowed)
}

func testTerminalAutomationDenialIsDenied() async {
    let client = SystemTerminalAutomationClient { _ in
        .failure(.appleEventNotPermitted)
    }
    XCTAssertEqual(await client.test(), .denied)
}

func testTerminalAutomationOtherFailureIsReported() async {
    let client = SystemTerminalAutomationClient { _ in
        .failure(.executionFailed("Terminal unavailable"))
    }
    XCTAssertEqual(await client.test(), .failed("Terminal unavailable"))
}

func testTerminalProbeIsReadOnly() {
    XCTAssertEqual(
        SystemTerminalAutomationClient.probeScript,
        "tell application \"Terminal\" to get name"
    )
}
```

- [ ] **Step 2: Run Terminal tests and verify RED**

Run:

```bash
swift test --filter PermissionSetupTests.testTerminal
```

Expected: compilation fails because the Terminal automation types do not exist.

- [ ] **Step 3: Implement the read-only Apple Event probe**

Append to `PermissionSetup.swift`:

```swift
enum TerminalAutomationError: Error, Equatable {
    case appleEventNotPermitted
    case executionFailed(String)
}

protocol TerminalAutomationClient {
    func test() async -> PermissionAccessStatus
}

struct SystemTerminalAutomationClient: TerminalAutomationClient {
    static let probeScript = "tell application \"Terminal\" to get name"
    var runner: (String) -> Result<Void, TerminalAutomationError> = Self.run

    func test() async -> PermissionAccessStatus {
        switch runner(Self.probeScript) {
        case .success: return .allowed
        case .failure(.appleEventNotPermitted): return .denied
        case .failure(.executionFailed(let message)): return .failed(message)
        }
    }

    private static func run(_ source: String) -> Result<Void, TerminalAutomationError> {
        var details: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure(.executionFailed("failed to create AppleScript"))
        }
        script.executeAndReturnError(&details)
        if let details {
            let number = details[NSAppleScript.errorNumber] as? Int
            if number == -1743 { return .failure(.appleEventNotPermitted) }
            let message = details[NSAppleScript.errorMessage] as? String ?? details.description
            return .failure(.executionFailed(message))
        }
        return .success(())
    }
}
```

Add `import AppKit` to `PermissionSetup.swift`.

- [ ] **Step 4: Run Terminal tests and verify GREEN**

Run:

```bash
swift test --filter PermissionSetupTests.testTerminal
```

Expected: all four Terminal tests pass without opening Terminal.

- [ ] **Step 5: Write failing login-item adapter tests**

Append test doubles and a behavior test to `PermissionSetupTests.swift`:

```swift
@MainActor
func testLoginItemManagerForwardsInjectedOperations() {
    var enabled = false
    let manager = ClosureLoginItemManager(
        isSupported: true,
        getEnabled: { enabled },
        setEnabled: { enabled = $0 }
    )

    XCTAssertTrue(manager.isSupported)
    XCTAssertFalse(manager.isEnabled)
    manager.setEnabled(true)
    XCTAssertTrue(manager.isEnabled)
}
```

- [ ] **Step 6: Run login-item test and verify RED**

Run:

```bash
swift test --filter PermissionSetupTests.testLoginItemManager
```

Expected: compilation fails because `ClosureLoginItemManager` does not exist.

- [ ] **Step 7: Introduce the login-item protocol and adapters**

Replace the static `LoginItem` API with these types in `LoginItem.swift`:

```swift
import Foundation
import ServiceManagement

protocol LoginItemManaging {
    var isSupported: Bool { get }
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
}

struct SystemLoginItemManager: LoginItemManaging {
    var isSupported: Bool { Bundle.main.bundleIdentifier != nil }
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) {
        guard isSupported else { return }
        do {
            enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister()
        } catch {
            NSLog("Ohayo LoginItem: \(error)")
        }
    }
}

struct ClosureLoginItemManager: LoginItemManaging {
    let isSupported: Bool
    let getEnabled: () -> Bool
    let setEnabledAction: (Bool) -> Void

    init(isSupported: Bool, getEnabled: @escaping () -> Bool,
         setEnabled: @escaping (Bool) -> Void) {
        self.isSupported = isSupported
        self.getEnabled = getEnabled
        self.setEnabledAction = setEnabled
    }

    var isEnabled: Bool { getEnabled() }
    func setEnabled(_ enabled: Bool) { setEnabledAction(enabled) }
}
```

- [ ] **Step 8: Declare the Apple Events purpose and validate the plist**

Add to `scripts/Info.plist` before `NSHighResolutionCapable`:

```xml
<key>NSAppleEventsUsageDescription</key>
<string>Ohayo uses Terminal to open the Claude Code and Codex sessions you start.</string>
```

Run:

```bash
plutil -lint scripts/Info.plist
```

Expected: `scripts/Info.plist: OK`.

- [ ] **Step 9: Run focused tests and commit**

Run:

```bash
swift test --filter PermissionSetupTests
```

Expected: all permission-client tests pass.

Commit:

```bash
git add Sources/Ohayo/PermissionSetup.swift Sources/Ohayo/LoginItem.swift Tests/OhayoTests/PermissionSetupTests.swift scripts/Info.plist
git commit -m "feat: add Terminal automation permission check"
```

---

### Task 4: Build the setup model and non-blocking guide window

**Files:**
- Modify: `Sources/Ohayo/PermissionSetup.swift`
- Create: `Sources/Ohayo/PermissionSetupView.swift`
- Modify: `Sources/Ohayo/OhayoApp.swift`
- Modify: `Sources/Ohayo/GeneralTab.swift`
- Modify: `Sources/Ohayo/Localization.swift`
- Modify: `Tests/OhayoTests/PermissionSetupTests.swift`

**Interfaces:**
- Consumes: `NotificationPermissionClient`, `TerminalAutomationClient`, and `LoginItemManaging`.
- Produces: `@MainActor PermissionSetupModel` with published statuses and explicit action methods.
- Produces: `PermissionSetupView` that dismisses initial presentation on close or `Configure Later`.
- Produces: a `Window` scene with id `permissions` and a manual reopen button in `GeneralTab`.

- [ ] **Step 1: Write failing model tests with explicit fakes**

Append to `PermissionSetupTests.swift`:

```swift
private actor NotificationFake: NotificationPermissionClient {
    var current: PermissionAccessStatus
    private(set) var requestCount = 0

    init(_ current: PermissionAccessStatus) { self.current = current }
    func status() async -> PermissionAccessStatus { current }
    func request() async -> PermissionAccessStatus {
        requestCount += 1
        current = .allowed
        return current
    }
}

private actor TerminalFake: TerminalAutomationClient {
    let result: PermissionAccessStatus
    private(set) var testCount = 0

    init(_ result: PermissionAccessStatus) { self.result = result }
    func test() async -> PermissionAccessStatus {
        testCount += 1
        return result
    }
}

@MainActor
func testModelRefreshDoesNotRequestPermissions() async {
    let notifications = NotificationFake(.notConfigured)
    let terminal = TerminalFake(.allowed)
    let login = ClosureLoginItemManager(
        isSupported: true, getEnabled: { false }, setEnabled: { _ in })
    let model = PermissionSetupModel(
        notifications: notifications, terminal: terminal, loginItem: login)

    await model.refresh()

    XCTAssertEqual(model.notificationStatus, .notConfigured)
    XCTAssertEqual(model.terminalStatus, .notConfigured)
    XCTAssertEqual(await notifications.requestCount, 0)
    XCTAssertEqual(await terminal.testCount, 0)
}

@MainActor
func testNotificationActionRequestsAndRefreshesStatus() async {
    let notifications = NotificationFake(.notConfigured)
    let model = PermissionSetupModel(
        notifications: notifications,
        terminal: TerminalFake(.notConfigured),
        loginItem: ClosureLoginItemManager(
            isSupported: false, getEnabled: { false }, setEnabled: { _ in }))

    await model.requestNotifications()

    XCTAssertEqual(model.notificationStatus, .allowed)
    XCTAssertEqual(await notifications.requestCount, 1)
}

@MainActor
func testTerminalActionOnlyRunsWhenExplicitlyCalled() async {
    let terminal = TerminalFake(.denied)
    let model = PermissionSetupModel(
        notifications: NotificationFake(.notConfigured),
        terminal: terminal,
        loginItem: ClosureLoginItemManager(
            isSupported: false, getEnabled: { false }, setEnabled: { _ in }))

    XCTAssertEqual(await terminal.testCount, 0)
    await model.testTerminal()

    XCTAssertEqual(model.terminalStatus, .denied)
    XCTAssertEqual(await terminal.testCount, 1)
}
```

- [ ] **Step 2: Run model tests and verify RED**

Run:

```bash
swift test --filter PermissionSetupTests.testModel
swift test --filter PermissionSetupTests.testNotificationAction
swift test --filter PermissionSetupTests.testTerminalAction
```

Expected: compilation fails because `PermissionSetupModel` does not exist.

- [ ] **Step 3: Implement the minimal setup model**

Append to `PermissionSetup.swift`:

```swift
@MainActor
final class PermissionSetupModel: ObservableObject {
    @Published private(set) var notificationStatus: PermissionAccessStatus = .notConfigured
    @Published private(set) var terminalStatus: PermissionAccessStatus = .notConfigured
    @Published private(set) var loginItemEnabled: Bool
    let loginItemSupported: Bool

    private let notifications: NotificationPermissionClient
    private let terminal: TerminalAutomationClient
    private let loginItem: LoginItemManaging

    init(notifications: NotificationPermissionClient = SystemNotificationPermissionClient(),
         terminal: TerminalAutomationClient = SystemTerminalAutomationClient(),
         loginItem: LoginItemManaging = SystemLoginItemManager()) {
        self.notifications = notifications
        self.terminal = terminal
        self.loginItem = loginItem
        self.loginItemSupported = loginItem.isSupported
        self.loginItemEnabled = loginItem.isEnabled
    }

    func refresh() async {
        notificationStatus = await notifications.status()
        loginItemEnabled = loginItem.isEnabled
    }

    func requestNotifications() async {
        notificationStatus = await notifications.request()
    }

    func testTerminal() async {
        terminalStatus = await terminal.test()
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        loginItem.setEnabled(enabled)
        loginItemEnabled = loginItem.isEnabled
    }
}
```

- [ ] **Step 4: Run model tests and verify GREEN**

Run:

```bash
swift test --filter PermissionSetupTests
```

Expected: all permission setup tests pass.

- [ ] **Step 5: Add localized copy**

Add `L10n` properties for the exact visible concepts used by the guide:

```swift
var permissionGuideTitle: String { text(en: "Set Up Ohayo", pt: "Configurar o Ohayo") }
var permissionGuideIntro: String {
    text(en: "Choose which system integrations you want to configure now.",
         pt: "Escolha quais integrações do sistema deseja configurar agora.")
}
var notificationsPermissionTitle: String { text(en: "Notifications", pt: "Notificações") }
var notificationsPermissionBody: String {
    text(en: "Receive run results and failure alerts.",
         pt: "Receba resultados de execuções e alertas de falha.")
}
var allowNotifications: String { text(en: "Allow Notifications", pt: "Permitir notificações") }
var terminalAutomationTitle: String { text(en: "Terminal Automation", pt: "Automação do Terminal") }
var terminalAutomationBody: String {
    text(en: "Allow Ohayo to open the interactive sessions you start.",
         pt: "Permita que o Ohayo abra as sessões interativas que você iniciar.")
}
var testTerminal: String { text(en: "Test Terminal", pt: "Testar Terminal") }
var configureLater: String { text(en: "Configure Later", pt: "Configurar depois") }
var permissionsSettingsButton: String { text(en: "Permissions…", pt: "Permissões…") }
var optional: String { text(en: "Optional", pt: "Opcional") }
var permissionNotConfigured: String { text(en: "Not configured", pt: "Não configurado") }
var permissionAllowed: String { text(en: "Allowed", pt: "Permitido") }
var permissionDenied: String { text(en: "Denied", pt: "Negado") }
var permissionFailed: String { text(en: "Unavailable", pt: "Indisponível") }
```

Add a formatter:

```swift
func permissionStatus(_ status: PermissionAccessStatus) -> String {
    switch status {
    case .notConfigured: return permissionNotConfigured
    case .allowed: return permissionAllowed
    case .denied: return permissionDenied
    case .failed: return permissionFailed
    }
}
```

- [ ] **Step 6: Create the guide view**

Create `Sources/Ohayo/PermissionSetupView.swift` with a `Form` containing three un-nested sections:

```swift
import SwiftUI

struct PermissionSetupView: View {
    @ObservedObject var state: AppState
    @StateObject private var model: PermissionSetupModel
    @Environment(\.dismiss) private var dismiss
    private var strings: L10n { state.strings }

    init(state: AppState, model: PermissionSetupModel = PermissionSetupModel()) {
        self.state = state
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(strings.permissionGuideTitle).font(.title2).bold()
            Text(strings.permissionGuideIntro).foregroundStyle(.secondary)
            Form {
                permissionRow(
                    title: strings.notificationsPermissionTitle,
                    body: strings.notificationsPermissionBody,
                    status: model.notificationStatus,
                    actionTitle: strings.allowNotifications
                ) { Task { await model.requestNotifications() } }
                permissionRow(
                    title: strings.terminalAutomationTitle,
                    body: strings.terminalAutomationBody,
                    status: model.terminalStatus,
                    actionTitle: strings.testTerminal
                ) { Task { await model.testTerminal() } }
                if model.loginItemSupported {
                    Toggle(strings.launchAtLogin, isOn: Binding(
                        get: { model.loginItemEnabled },
                        set: { model.setLoginItemEnabled($0) }))
                    Text(strings.optional).font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(strings.configureLater) { closeGuide() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
        .task { await model.refresh() }
        .onDisappear { state.dismissPermissionGuide() }
    }

    private func closeGuide() {
        state.dismissPermissionGuide()
        dismiss()
    }

    private func permissionRow(
        title: String, body: String, status: PermissionAccessStatus,
        actionTitle: String, action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(strings.permissionStatus(status)).foregroundStyle(.secondary)
            }
            Text(body).font(.callout).foregroundStyle(.secondary)
            Button(actionTitle, action: action)
                .disabled(status == .allowed)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 7: Register the window and automatic opening**

In `OhayoApp.body`, keep the existing menu content unchanged and attach the
coordinator to the menu-bar label, which SwiftUI renders at application launch:

```swift
MenuBarLabel(state: env.state)
    .background {
        StartupCoordinatorView(
            state: env.state,
            isBundled: Bundle.main.bundleIdentifier != nil
        )
    }
```

Add a separate scene:

```swift
Window(env.state.strings.permissionGuideTitle, id: "permissions") {
    PermissionSetupView(state: env.state)
}
.windowResizability(.contentSize)
```

Keep the existing Settings window unchanged.

- [ ] **Step 8: Add manual reopening and migrate General settings to the adapter**

In `GeneralTab`, add:

```swift
@Environment(\.openWindow) private var openWindow
private let loginItem: LoginItemManaging = SystemLoginItemManager()
```

Replace static login-item reads with `loginItem.isSupported`, `loginItem.isEnabled`, and `loginItem.setEnabled(_:)`. Add this command to the version section:

```swift
Button {
    openWindow(id: "permissions")
} label: {
    Label(strings.permissionsSettingsButton, systemImage: "checklist")
}
```

- [ ] **Step 9: Run the full test suite and commit**

Run:

```bash
swift test
```

Expected: all tests pass; no test opens a system authorization prompt or Terminal.

Commit:

```bash
git add Sources/Ohayo/PermissionSetup.swift Sources/Ohayo/PermissionSetupView.swift Sources/Ohayo/StartupCoordinatorView.swift Sources/Ohayo/OhayoApp.swift Sources/Ohayo/GeneralTab.swift Sources/Ohayo/Localization.swift Tests/OhayoTests/PermissionSetupTests.swift
git commit -m "feat: add non-blocking permission setup guide"
```

---

### Task 5: Document and verify the packaged first-run experience

**Files:**
- Modify: `README.md`
- Modify: `README.pt-br.md`
- Verify: `scripts/make-app.sh`
- Verify: `build/Ohayo.app/Contents/Info.plist`

**Interfaces:**
- Consumes: the completed guide, `NSAppleEventsUsageDescription`, and packaging script.
- Produces: user-facing setup and recovery instructions plus runtime evidence from the packaged app.

- [ ] **Step 1: Update English documentation**

Add a `First-run permissions` subsection to `README.md` after the Settings overview. State exactly:

```markdown
### First-run permissions

The packaged app opens a non-blocking setup guide once. You can allow
notifications, test the Terminal automation used for interactive sessions, and
optionally enable Launch at Login. Closing the guide does not disable the app;
reopen it from **Settings → General → Permissions…**.

If notifications or Terminal automation were denied, change them in **System
Settings → Notifications → Ohayo** or **System Settings → Privacy & Security →
Automation**, then reopen the guide to refresh or test the integration.
```

- [ ] **Step 2: Update Portuguese documentation**

Add the equivalent subsection to `README.pt-br.md`:

```markdown
### Permissões na primeira abertura

O app empacotado abre uma única vez um guia não bloqueante. Nele você pode
permitir notificações, testar a automação do Terminal usada nas sessões
interativas e, opcionalmente, ativar **Iniciar com o Mac**. Fechar o guia não
desativa o app; reabra-o em **Ajustes → Geral → Permissões…**.

Se notificações ou automação do Terminal forem negadas, altere-as em **Ajustes
do Sistema → Notificações → Ohayo** ou **Ajustes do Sistema → Privacidade e
Segurança → Automação** e reabra o guia para atualizar ou testar a integração.
```

- [ ] **Step 3: Run automated verification**

Run:

```bash
swift test
./scripts/make-app.sh
plutil -p build/Ohayo.app/Contents/Info.plist
codesign --verify --deep --strict build/Ohayo.app
```

Expected:

- all Swift tests pass;
- `build/Ohayo.app` is generated;
- the plist output contains `NSAppleEventsUsageDescription` with the Ohayo Terminal explanation;
- `codesign` exits with status 0 and no verification error.

- [ ] **Step 4: Perform the packaged-app smoke test and restore the original guide flag**

Before opening the app, preserve the current guide flag and force only that key
to the first-run state in the bundle domain:

```bash
original_guide_flag="$(defaults read io.github.hayashirafael.Ohayo hasDismissedPermissionGuide 2>/dev/null || echo __missing__)"
defaults delete io.github.hayashirafael.Ohayo hasDismissedPermissionGuide 2>/dev/null || true
open build/Ohayo.app
```

Verify manually:

- the guide opens as a separate window and the menu remains usable;
- closing the guide keeps Ohayo running;
- reopening from General works;
- merely opening the guide causes no macOS prompt and does not open Terminal;
- `Allow Notifications` is the only action that requests notifications;
- `Test Terminal` is the only guide action that sends the Terminal Apple Event;
- `Configure Later` prevents automatic opening on the next launch;
- login at launch is visibly optional.

After the smoke test, quit Ohayo and restore only the preserved key:

```bash
if [[ "$original_guide_flag" == "__missing__" ]]; then
    defaults delete io.github.hayashirafael.Ohayo hasDismissedPermissionGuide 2>/dev/null || true
else
    defaults write io.github.hayashirafael.Ohayo hasDismissedPermissionGuide -bool "$original_guide_flag"
fi
```

- [ ] **Step 5: Commit documentation**

```bash
git add README.md README.pt-br.md
git commit -m "docs: explain first-run permission setup"
```

- [ ] **Step 6: Review the complete implementation diff**

Run:

```bash
git status --short
git log --oneline -5
git diff HEAD~5 --check
```

Expected: the worktree contains no unintended source changes, the five feature commits are visible, and the diff check reports no whitespace errors.
