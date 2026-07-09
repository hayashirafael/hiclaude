import SwiftUI

struct HistoryTab: View {
    @ObservedObject var state: AppState

    var body: some View {
        if state.history.isEmpty {
            Text("Sem disparos registrados ainda.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
                .padding(40)
        } else {
            Form {
                Section {
                    ForEach(Array(state.history.enumerated()), id: \.offset) { _, event in
                        row(event)
                    }
                } footer: {
                    Text("Últimos \(AppState.historyLimit) disparos, mais recentes primeiro.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func row(_ event: FireEvent) -> some View {
        if let response = event.response, !response.isEmpty {
            DisclosureGroup {
                Text(response)
                    .font(.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                header(event)
            }
        } else {
            header(event)
        }
    }

    private func header(_ event: FireEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol(event)).foregroundStyle(color(event))
            VStack(alignment: .leading, spacing: 1) {
                Text(title(event))
                if !subtitle(event).isEmpty {
                    Text(subtitle(event)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func symbol(_ event: FireEvent) -> String {
        if event.origin == .renewal { return "arrow.triangle.2.circlepath" }
        switch event.result {
        case .success: return "checkmark.circle"
        case .skipped: return "arrow.uturn.right.circle"
        case .failure: return "xmark.circle"
        }
    }

    private func color(_ event: FireEvent) -> Color {
        switch event.result {
        case .success: return .green
        case .skipped: return .secondary
        case .failure: return .red
        }
    }

    private func title(_ event: FireEvent) -> String {
        let time = Fmt.dayTime(event.date)
        switch event.result {
        case .success: return "\(time) — \(event.messageText ?? "hi")"
        case .skipped(let until): return "\(time) — pulado (janela até \(Fmt.hhmm(until)))"
        case .failure(let message): return "\(time) — falhou: \(message)"
        }
    }

    private func subtitle(_ event: FireEvent) -> String {
        var parts: [String] = []
        if let account = event.account { parts.append(account) }
        switch event.origin {
        case .manual: parts.append("manual")
        case .renewal: parts.append("renovação")
        case .scheduled, .none: break
        }
        return parts.joined(separator: " · ")
    }
}
