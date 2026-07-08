import SwiftUI

struct ScheduleView: View {
    @ObservedObject var state: AppState
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Horários do hi diário").font(.headline)
            Text("Todos os dias, nos horários abaixo.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(Array(state.times.enumerated()), id: \.offset) { index, _ in
                HStack {
                    DatePicker("", selection: timeBinding(at: index),
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer()
                    Button {
                        state.times.remove(at: index)
                        onChange()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                state.times.append(9 * 60)
                onChange()
            } label: {
                Label("Adicionar horário", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: 280)
    }

    private func timeBinding(at index: Int) -> Binding<Date> {
        Binding(
            get: {
                guard state.times.indices.contains(index) else { return Date() }
                let minutes = state.times[index]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                             second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                guard state.times.indices.contains(index) else { return }
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                state.times[index] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                onChange()
            }
        )
    }
}
