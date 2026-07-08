import Foundation

struct ScheduleRow: Identifiable, Equatable {
    let id: UUID
    var minutes: Int

    init(id: UUID = UUID(), minutes: Int) {
        self.id = id
        self.minutes = minutes
    }
}

struct ScheduleRows: Equatable {
    private(set) var rows: [ScheduleRow]

    init(times: [Int]) {
        self.rows = times.sorted().map { ScheduleRow(minutes: $0) }
    }

    var publishedTimes: [Int] {
        rows.map(\.minutes).sorted()
    }

    mutating func sync(from times: [Int]) {
        guard publishedTimes != times.sorted() else { return }
        rows = times.sorted().map { ScheduleRow(minutes: $0) }
    }

    mutating func update(id: UUID, minutes: Int) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].minutes = minutes
        rows.sort { lhs, rhs in
            if lhs.minutes == rhs.minutes {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.minutes < rhs.minutes
        }
    }

    mutating func remove(id: UUID) {
        rows.removeAll { $0.id == id }
    }

    mutating func append(minutes: Int) {
        rows.append(ScheduleRow(minutes: minutes))
        rows.sort { lhs, rhs in
            if lhs.minutes == rhs.minutes {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.minutes < rhs.minutes
        }
    }
}
