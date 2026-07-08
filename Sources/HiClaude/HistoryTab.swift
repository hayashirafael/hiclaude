import SwiftUI

struct HistoryTab: View {
    @ObservedObject var state: AppState

    var body: some View {
        Text("Sem disparos registrados ainda.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 200)
            .padding(40)
    }
}
