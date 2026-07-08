import SwiftUI

struct SchedulesTab: View {
    @ObservedObject var state: AppState
    let onChange: () -> Void

    var body: some View {
        Form {
            Section {
                ForEach(state.schedules) { entry in
                    HStack {
                        DatePicker("", selection: timeBinding(entry),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Picker("", selection: messageBinding(entry)) {
                            Text("Ativa (padrão)").tag(UUID?.none)
                            ForEach(state.allMessages) { msg in
                                Text(msg.text).tag(msg.uid)
                            }
                        }
                        .labelsHidden()
                        Button {
                            state.removeSchedule(id: entry.id)
                            onChange()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    state.addSchedule(minutes: 9 * 60)
                    onChange()
                } label: {
                    Label("Adicionar horário", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Todos os dias, nos horários acima. Cada horário pode fixar uma mensagem ou seguir a ativa.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func timeBinding(_ entry: ScheduleEntry) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: entry.minutes / 60,
                                      minute: entry.minutes % 60,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                state.updateSchedule(id: entry.id,
                                     minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
                onChange()
            }
        )
    }

    private func messageBinding(_ entry: ScheduleEntry) -> Binding<UUID?> {
        Binding(
            get: { entry.messageUID },
            set: { state.setScheduleMessage(id: entry.id, messageUID: $0) }
        )
    }
}
