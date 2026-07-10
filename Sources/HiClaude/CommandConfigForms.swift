import AppKit
import SwiftUI

struct ClaudeConfigForm: View {
    @Binding var model: Message.Model
    @Binding var effort: Message.Effort
    @Binding var safeMode: Bool
    @Binding var configDir: String?
    @Binding var workingDir: String
    let accounts: [URL]
    let accountLabel: (URL) -> String
    let strings: L10n

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
            GridRow {
                ConfigRowLabel(strings.model)
                Picker("", selection: $model) {
                    ForEach(Message.Model.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
            }
            GridRow {
                ConfigRowLabel("Effort")
                Picker("", selection: $effort) {
                    ForEach(Message.Effort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
            }
            GridRow {
                ConfigRowLabel(strings.account)
                Picker("", selection: $configDir) {
                    Text(strings.globalDefault).tag(String?.none)
                    ForEach(accounts, id: \.self) { dir in
                        Text(accountLabel(dir)).tag(String?.some(dir.path))
                    }
                }
                .labelsHidden()
            }
            GridRow {
                ConfigRowLabel("")
                WorkingDirectoryPicker(workingDir: $workingDir, strings: strings)
            }
            GridRow {
                ConfigRowLabel("")
                Toggle("Safe mode", isOn: $safeMode).toggleStyle(.checkbox)
            }
        }
        .font(.caption)
    }
}

struct CodexConfigForm: View {
    @Binding var model: String
    @Binding var reasoning: Message.CodexReasoning
    @Binding var configDir: String?
    @Binding var workingDir: String
    let accounts: [URL]
    let accountLabel: (URL) -> String
    let strings: L10n

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
            GridRow {
                ConfigRowLabel(strings.model)
                TextField(strings.accountDefaultModel, text: $model)
            }
            GridRow {
                ConfigRowLabel("Reasoning")
                Picker("", selection: $reasoning) {
                    ForEach(Message.CodexReasoning.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
            }
            GridRow {
                ConfigRowLabel(strings.account)
                Picker("", selection: $configDir) {
                    Text(strings.codexDefault).tag(String?.none)
                    ForEach(accounts, id: \.self) { dir in
                        Text(accountLabel(dir)).tag(String?.some(dir.path))
                    }
                }
                .labelsHidden()
            }
            GridRow {
                ConfigRowLabel("")
                WorkingDirectoryPicker(workingDir: $workingDir, strings: strings)
            }
        }
        .font(.caption)
    }
}

/// Rótulo da coluna esquerda dos forms de config: coluna alinhada e discreta.
struct ConfigRowLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }
}

struct WorkingDirectoryPicker: View {
    @Binding var workingDir: String
    let strings: L10n

    private var isEmpty: Bool {
        workingDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayText: String {
        isEmpty ? strings.workingDirectoryDefault
            : (workingDir as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: chooseDirectory) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(displayText)
                        .foregroundStyle(isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .help(strings.workingDirectoryDefault)

            if !isEmpty {
                Button { workingDir = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .help(strings.clearWorkingDirectory)
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = strings.chooseDirectory
        panel.directoryURL = initialDirectoryURL()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workingDir = url.standardizedFileURL.path
    }

    private func initialDirectoryURL() -> URL {
        guard !isEmpty else { return FileManager.default.homeDirectoryForCurrentUser }
        let expanded = NSString(string: workingDir).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return URL(fileURLWithPath: expanded)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
