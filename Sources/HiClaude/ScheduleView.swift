import SwiftUI

struct ScheduleView: View {
    @ObservedObject var state: AppState
    let onChange: () -> Void
    @State private var scheduleRows: ScheduleRows
    @State private var newMessage = ""

    init(state: AppState, onChange: @escaping () -> Void) {
        self.state = state
        self.onChange = onChange
        self._scheduleRows = State(initialValue: ScheduleRows(times: state.times))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Horários do hi diário").font(.headline)
            Text("Todos os dias, nos horários abaixo.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(scheduleRows.rows) { row in
                HStack {
                    DatePicker("", selection: timeBinding(id: row.id),
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer()
                    Button {
                        scheduleRows.remove(id: row.id)
                        publishRows()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                scheduleRows.append(minutes: 9 * 60)
                publishRows()
            } label: {
                Label("Adicionar horário", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)

            Divider()
            Text("Mensagens").font(.headline)
            Text("Enviada ao Claude para abrir a janela. Escolha a ativa.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(state.allMessages, id: \.self) { msg in
                HStack {
                    Button {
                        state.setActiveMessage(msg)
                    } label: {
                        Image(systemName: msg == state.resolvedMessage
                              ? "largecircle.fill.circle" : "circle")
                    }
                    .buttonStyle(.plain)

                    Text(msg)
                    Spacer()

                    if msg != AppState.defaultMessage {
                        Button {
                            state.removeFavorite(msg)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                TextField("Nova mensagem", text: $newMessage)
                Button("Adicionar") {
                    state.addFavorite(newMessage)
                    newMessage = ""
                }
            }
        }
        .onChange(of: state.times) { newTimes in
            scheduleRows.sync(from: newTimes)
        }
        .padding(20)
        .frame(width: 280)
    }

    private func timeBinding(id: ScheduleRow.ID) -> Binding<Date> {
        Binding(
            get: {
                guard let minutes = scheduleRows.rows.first(where: { $0.id == id })?.minutes else {
                    return Date()
                }
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                             second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                scheduleRows.update(id: id, minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
                publishRows()
            }
        )
    }

    private func publishRows() {
        state.times = scheduleRows.publishedTimes
        onChange()
    }
}
