import Foundation

enum UpdateCheckAge {
    static func label(for date: Date?, now: Date) -> String {
        guard let date, date <= now else { return "N.A." }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "Checked \(max(seconds, 0))s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "Checked \(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 {
            return hours == 1 ? "Checked 1 hour ago" : "Checked \(hours) hours ago"
        }
        let days = hours / 24
        if days < 30 {
            return days == 1 ? "Checked 1 day ago" : "Checked \(days) days ago"
        }
        let months = days / 30
        if months < 12 {
            return months == 1 ? "Checked 1 month ago" : "Checked \(months) months ago"
        }
        let years = months / 12
        return years == 1 ? "Checked 1 year ago" : "Checked \(years) years ago"
    }

    static func accessibilityLabel(for date: Date?, now: Date) -> String {
        let text = label(for: date, now: now)
        return text == "N.A." ? "Never checked for updates" : text
    }

    /// Exactly the next boundary at which the existing label can change.
    static func nextRefresh(for date: Date?, after now: Date) -> Date? {
        guard let date else { return nil }
        if date > now { return date }
        let elapsed = now.timeIntervalSince(date)
        let unit: TimeInterval
        if elapsed < 60 { unit = 1 }
        else if elapsed < 3600 { unit = 60 }
        else if elapsed < 86400 { unit = 3600 }
        else if elapsed < 30 * 86400 { unit = 86400 }
        else if elapsed < 360 * 86400 { unit = 30 * 86400 }
        else { unit = 360 * 86400 }
        return date.addingTimeInterval((floor(elapsed / unit) + 1) * unit)
    }
}
