import SwiftUI

struct HistoryTab: View {
    @ObservedObject var state: AppState
    private var strings: L10n { state.strings }

    var body: some View {
        if state.history.isEmpty {
            Text(strings.noHistory)
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
                    Text(strings.historyFooter(limit: AppState.historyLimit))
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
        if event.origin == .agenda { return "calendar" }
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
        let time = Fmt.dayTime(event.date, language: state.language)
        switch event.result {
        case .success:
            return strings.succeeded(time, event.messageText ?? "hi")
        case .skipped(let until):
            return strings.skippedUntil(time, Fmt.hhmm(until, language: state.language))
        case .failure(let message):
            return strings.failed(time, message)
        }
    }

    private func subtitle(_ event: FireEvent) -> String {
        var parts: [String] = []
        if let account = event.account { parts.append(account) }
        if let origin = event.origin, let label = strings.origin(origin) {
            parts.append(label)
        }
        return parts.joined(separator: " · ")
    }
}
