import SwiftUI

@MainActor
struct PermissionSetupView: View {
    @ObservedObject var state: AppState
    @StateObject private var model: PermissionSetupModel
    @Environment(\.dismiss) private var dismiss
    private var strings: L10n { state.strings }

    init(state: AppState, model: PermissionSetupModel? = nil) {
        self.state = state
        _model = StateObject(wrappedValue: model ?? PermissionSetupModel())
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
