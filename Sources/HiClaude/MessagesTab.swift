import SwiftUI

struct MessagesTab: View {
    @ObservedObject var state: AppState
    @State private var showingForm = false
    @State private var editing: Message? = nil

    var body: some View {
        Form {
            Section {
                ForEach(state.allMessages) { msg in row(msg) }
                Button {
                    editing = nil
                    showingForm = true
                } label: {
                    Label("Nova mensagem", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Biblioteca de mensagens. Atribua uma a cada conta na aba Contas. Com Claude: abre a janela de 5h. Sem Claude: roda o texto como comando.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingForm) {
            MessageFormSheet(state: state, editing: editing) { _ in showingForm = false }
        }
    }

    @ViewBuilder
    private func row(_ msg: Message) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(msg.text)
                if let badge = configBadge(msg) {
                    Text(badge).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if msg != AppState.defaultMessage {
                Button { editing = msg; showingForm = true } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                Button { state.removeFavorite(msg) } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Resumo compacto da config não-default (ex: "Opus 4.8 · high · resposta").
    private func configBadge(_ msg: Message) -> String? {
        var parts: [String] = []
        if msg.kind == .shell { parts.append("comando") }
        if msg.model != nil { parts.append(msg.resolvedModel.label) }
        if msg.effort != nil { parts.append(msg.resolvedEffort.rawValue) }
        if msg.safeMode == false { parts.append("sem safe") }
        if let c = msg.configDir, !c.isEmpty { parts.append(state.label(for: URL(fileURLWithPath: c))) }
        if let w = msg.workingDir, !w.isEmpty { parts.append(URL(fileURLWithPath: w).lastPathComponent) }
        if msg.resolvedShowResponse { parts.append("resposta") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
