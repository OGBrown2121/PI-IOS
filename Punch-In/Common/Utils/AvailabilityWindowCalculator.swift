import Foundation

enum AvailabilityWindowCalculator {
    static func baseWindows(
        schedule: StudioOperatingSchedule,
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> [DateInterval] {
        if schedule.recurringHours.isEmpty {
            return [DateInterval(start: dayStart, end: dayEnd)]
        }

        let weekdayComponent = calendar.component(.weekday, from: dayStart)
        let normalizedWeekday = (weekdayComponent + 6) % 7

        let windows = schedule.recurringHours
            .filter { $0.weekday == normalizedWeekday }
            .sorted { $0.startTimeMinutes < $1.startTimeMinutes }

        return windows.compactMap { window in
            guard let start = calendar.date(byAdding: .minute, value: window.startTimeMinutes, to: dayStart) else {
                return nil
            }
            let end = min(start.addingTimeInterval(TimeInterval(window.durationMinutes * 60)), dayEnd)
            guard start < end else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    static func clampedInterval(
        for booking: Booking,
        dayStart: Date,
        dayEnd: Date
    ) -> DateInterval? {
        let start = booking.confirmedStart ?? booking.requestedStart
        let end = booking.confirmedEnd ?? booking.requestedEnd
        let clampedStart = max(start, dayStart)
        let clampedEnd = min(end, dayEnd)
        guard clampedStart < clampedEnd else { return nil }
        return DateInterval(start: clampedStart, end: clampedEnd)
    }

    static func interval(
        for entry: AvailabilityEntry,
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> DateInterval? {
        guard let startDate = entry.startDate, let endDate = entry.endDate else { return nil }
        let clampedStart = max(startDate, dayStart)
        let clampedEnd = min(endDate, dayEnd)
        guard clampedStart < clampedEnd else { return nil }
        return DateInterval(start: clampedStart, end: clampedEnd)
    }

    static func recurringInterval(
        for entry: AvailabilityEntry,
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> DateInterval? {
        guard let weekday = entry.weekday, let startMinutes = entry.startTimeMinutes else { return nil }

        let weekdayComponent = calendar.component(.weekday, from: dayStart)
        let normalizedWeekday = (weekdayComponent + 6) % 7
        guard weekday == normalizedWeekday else { return nil }

        guard let start = calendar.date(byAdding: .minute, value: startMinutes, to: dayStart) else {
            return nil
        }
        let end = min(start.addingTimeInterval(TimeInterval(entry.durationMinutes * 60)), dayEnd)
        guard start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func subtract(_ intervals: [DateInterval], removing removal: DateInterval) -> [DateInterval] {
        guard removal.duration > 0 else { return intervals }

        var result: [DateInterval] = []

        for interval in intervals {
            guard interval.intersects(removal) else {
                result.append(interval)
                continue
            }

            let overlapStart = max(interval.start, removal.start)
            let overlapEnd = min(interval.end, removal.end)
            guard overlapStart < overlapEnd else {
                result.append(interval)
                continue
            }

            if interval.start < overlapStart {
                result.append(DateInterval(start: interval.start, end: overlapStart))
            }

            if overlapEnd < interval.end {
                result.append(DateInterval(start: overlapEnd, end: interval.end))
            }
        }

        return result
    }

    static func mergeOverlapping(_ intervals: [DateInterval]) -> [DateInterval] {
        guard intervals.isEmpty == false else { return [] }

        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        var current = sorted[0]

        for interval in sorted.dropFirst() {
            if current.end >= interval.start {
                current = DateInterval(
                    start: min(current.start, interval.start),
                    end: max(current.end, interval.end)
                )
            } else {
                merged.append(current)
                current = interval
            }
        }

        merged.append(current)
        return merged
    }

    static func timeFormatter(timezone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = timezone
        return formatter
    }
}
