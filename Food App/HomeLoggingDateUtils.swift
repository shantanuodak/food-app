import Foundation

/// Shared date formatting and day normalization for the home logging flow.
enum HomeLoggingDateUtils {
    static let loggedAtFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let summaryRequestFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static let topDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static func draftTimestamp(for selectedSummaryDate: Date, reference: Date = Date()) -> Date {
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: selectedSummaryDate)
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: reference)
        var components = calendar.dateComponents([.year, .month, .day], from: selectedDay)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        components.nanosecond = time.nanosecond
        let timestamp = calendar.date(from: components) ?? selectedDay
        return min(timestamp, reference)
    }

    static func clampedSummaryDate(_ date: Date) -> Date {
        let normalized = Calendar.current.startOfDay(for: date)
        let today = Calendar.current.startOfDay(for: Date())
        return min(normalized, today)
    }
}
