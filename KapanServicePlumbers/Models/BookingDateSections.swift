import Foundation

/// Groups bookings by local calendar day of `scheduledAt` for List section headers.
struct BookingDaySection: Identifiable, Equatable {
    let id: String
    let dayStart: Date
    let title: String
    let bookings: [MobileBooking]
}

enum BookingDateSections {
    /// Section title: Today / Tomorrow / “September 15” (local calendar).
    static func sectionTitle(for dayStart: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
        if calendar.isDateInToday(dayStart) { return "Today" }
        if calendar.isDateInTomorrow(dayStart) { return "Tomorrow" }
        if calendar.isDateInYesterday(dayStart) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        // Include year when not current year.
        if calendar.component(.year, from: dayStart) == calendar.component(.year, from: now) {
            formatter.setLocalizedDateFormatFromTemplate("MMMM d")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMMM d, yyyy")
        }
        return formatter.string(from: dayStart)
    }

    /// Group by local day of `scheduledAt`. Sections chronological; within section by time.
    /// - Parameter reverseDays: when true (Done history), newest day first.
    static func group(
        _ bookings: [MobileBooking],
        calendar: Calendar = .current,
        now: Date = Date(),
        reverseDays: Bool = false
    ) -> [BookingDaySection] {
        var buckets: [Date: [MobileBooking]] = [:]
        var undated: [MobileBooking] = []

        for booking in bookings {
            guard let scheduled = booking.scheduledDate else {
                undated.append(booking)
                continue
            }
            let day = calendar.startOfDay(for: scheduled)
            buckets[day, default: []].append(booking)
        }

        var days = buckets.keys.sorted()
        if reverseDays { days.reverse() }

        var sections: [BookingDaySection] = days.map { day in
            let rows = (buckets[day] ?? []).sorted { a, b in
                (a.scheduledDate ?? .distantPast) < (b.scheduledDate ?? .distantPast)
            }
            return BookingDaySection(
                id: ISO8601DateFormatter().string(from: day),
                dayStart: day,
                title: sectionTitle(for: day, calendar: calendar, now: now),
                bookings: rows
            )
        }

        if !undated.isEmpty {
            sections.append(
                BookingDaySection(
                    id: "undated",
                    dayStart: .distantPast,
                    title: "Schedule TBD",
                    bookings: undated
                )
            )
        }
        return sections
    }
}
