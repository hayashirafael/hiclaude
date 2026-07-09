import SwiftUI

/// Seção Contas: por conta, identidade + apelido + modo de renovação
/// (Off/Automática/Programada) + âncora + mensagem + status.
struct ContasView: View {
    @ObservedObject var state: AppState
    @State private var editingAlias: URL? = nil
    @State private var aliasDraft = ""
    /// Conta para a qual o sheet "Novo…" foi aberto; nil = fechado.
    @State private var newMessageFor: URL? = nil

    /// Tag sentinela do item "Novo…" no picker de comando.
    private static let newCommandSentinel = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

    var body: some View {
        Form {
            ForEach(state.discoverAccounts(), id: \.self) { dir in
                Section {
                    header(dir)
                    modePicker(dir)
                    if state.renewal(for: dir)?.mode == .scheduled {
                        anchorPicker(dir)
                    }
                    if state.renewal(for: dir) != nil {
                        messagePicker(dir)
                        Text(statusText(dir)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: Binding(
            get: { newMessageFor != nil },
            set: { if !$0 { newMessageFor = nil } })) {
            MessageFormSheet(state: state, editing: nil) { created in
                if let created, let dir = newMessageFor {
                    var c = state.renewal(for: dir) ?? AccountRenewal()
                    c.messageUID = created.uid
                    state.setRenewal(dir, c)
                }
                newMessageFor = nil
            }
        }
    }

    @ViewBuilder
    private func header(_ dir: URL) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                if editingAlias == dir {
                    TextField("Apelido", text: $aliasDraft, onCommit: { commitAlias(dir) })
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(state.label(for: dir))
                }
                if let email = state.email(for: dir), email != state.label(for: dir) {
                    Text(email).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                if editingAlias == dir { commitAlias(dir) }
                else { editingAlias = dir; aliasDraft = state.alias(for: dir) ?? "" }
            } label: {
                Image(systemName: editingAlias == dir ? "checkmark" : "pencil")
            }
            .buttonStyle(.plain)
        }
    }

    private func modePicker(_ dir: URL) -> some View {
        Picker("Renovação", selection: modeBinding(dir)) {
            Text("Off").tag(ModeChoice.off)
            Text("Automática").tag(ModeChoice.automatic)
            Text("Programada").tag(ModeChoice.scheduled)
        }
        .pickerStyle(.segmented)
    }

    private func anchorPicker(_ dir: URL) -> some View {
        DatePicker("Início diário", selection: anchorBinding(dir),
                   displayedComponents: .hourAndMinute)
    }

    private func messagePicker(_ dir: URL) -> some View {
        Picker("Comando", selection: messageBinding(dir)) {
            Text("1+1").tag(UUID?.none)
            ForEach(state.favorites) { msg in
                Text(msg.text).tag(msg.uid)
            }
            Divider()
            Text("Novo…").tag(UUID?.some(Self.newCommandSentinel))
        }
    }

    private func statusText(_ dir: URL) -> String {
        if let date = state.nextRenewals[dir.standardizedFileURL] {
            return "renovando · próxima \(Fmt.hhmm(date))"
        }
        return "aguardando janela"
    }

    // MARK: - Bindings

    private enum ModeChoice: Hashable { case off, automatic, scheduled }

    private func modeBinding(_ dir: URL) -> Binding<ModeChoice> {
        Binding(
            get: {
                switch state.renewal(for: dir)?.mode {
                case .some(.automatic): return .automatic
                case .some(.scheduled): return .scheduled
                case .none: return .off
                }
            },
            set: { choice in
                switch choice {
                case .off:
                    state.setRenewal(dir, nil)
                case .automatic:
                    var c = state.renewal(for: dir) ?? AccountRenewal()
                    c.mode = .automatic
                    state.setRenewal(dir, c)
                case .scheduled:
                    var c = state.renewal(for: dir) ?? AccountRenewal()
                    c.mode = .scheduled
                    if c.anchorMinutes == nil { c.anchorMinutes = AppState.defaultAnchorMinutes }
                    state.setRenewal(dir, c)
                }
            })
    }

    private func anchorBinding(_ dir: URL) -> Binding<Date> {
        Binding(
            get: {
                let m = state.renewal(for: dir)?.anchorMinutes ?? AppState.defaultAnchorMinutes
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let p = Calendar.current.dateComponents([.hour, .minute], from: date)
                var c = state.renewal(for: dir) ?? AccountRenewal(mode: .scheduled)
                c.mode = .scheduled
                c.anchorMinutes = (p.hour ?? 0) * 60 + (p.minute ?? 0)
                state.setRenewal(dir, c)
            })
    }

    private func messageBinding(_ dir: URL) -> Binding<UUID?> {
        Binding(
            get: { state.renewal(for: dir)?.messageUID },
            set: { uid in
                guard uid != Self.newCommandSentinel else {
                    newMessageFor = dir
                    return
                }
                var c = state.renewal(for: dir) ?? AccountRenewal()
                c.messageUID = uid
                state.setRenewal(dir, c)
            })
    }

    private func commitAlias(_ dir: URL) {
        state.setAlias(dir, aliasDraft)
        editingAlias = nil
    }
}
