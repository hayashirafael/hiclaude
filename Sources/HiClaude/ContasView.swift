import SwiftUI

/// Seção Contas: por conta, identidade + apelido + modo de renovação
/// (Off/Automática/Programada) + âncora + mensagem + status.
struct ContasView: View {
    @ObservedObject var state: AppState
    @State private var editingAlias: URL? = nil
    @State private var aliasDraft = ""

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
        Picker("Mensagem", selection: messageBinding(dir)) {
            Text("Mínimo (1+1)").tag(UUID?.none)
            ForEach(state.allMessages) { msg in
                Text(msg.text).tag(msg.uid)
            }
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
