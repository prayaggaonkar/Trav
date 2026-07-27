import Foundation

/// A local pop-up event ingested by the data pipeline (Luma/Eventbrite/Reddit).
struct Popup: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var address: String
    var startTime: Date?
    var endTime: Date?

    var isUpcomingSoon: Bool {
        guard let startTime else { return false }
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let threeDaysOut = Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now
        return startTime >= startOfToday && startTime <= threeDaysOut
    }

    var startTimeLabel: String {
        guard let startTime else { return "Date/Time TBA" }
        if Calendar.current.isDateInToday(startTime) {
            return "Today at " + DateFormatter.localizedString(from: startTime, dateStyle: .none, timeStyle: .short)
        }
        if Calendar.current.isDateInTomorrow(startTime) {
            return "Tomorrow at " + DateFormatter.localizedString(from: startTime, dateStyle: .none, timeStyle: .short)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }
}
