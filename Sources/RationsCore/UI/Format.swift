import SwiftUI

enum Format {
    /// Round up to a whole minute; expired snapshots stay at 00:00 until refreshed.
    static func menuBarCountdown(to date: Date, from now: Date) -> String {
        let minutes = Int(ceil(max(0, date.timeIntervalSince(now)) / 60))
        let days = minutes / (24 * 60)
        let clock = String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
        return days > 0 ? "\(days)d \(clock)" : clock
    }

    static func menuBarValue(_ window: UsageWindow, options: MenuBarOptions, pinned: Bool = false, now: Date) -> String {
        if options.showsCountdown(for: window, pinned: pinned), let reset = window.resetsAt {
            return menuBarCountdown(to: reset, from: now)
        }
        return percent(window.percentUsed)
    }

    /// "4h 36m", "6d 5h", "12m", or "now".
    static func countdown(to date: Date, from now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 30 else { return "now" }
        let minutes = (seconds + 30) / 60
        let hours = minutes / 60
        let days = hours / 24
        switch (days, hours, minutes) {
        case (1..., _, _): return "\(days)d \(hours % 24)h"
        case (_, 1..., _): return "\(hours)h \(minutes % 60)m"
        default: return "\(minutes)m"
        }
    }

    /// "just now", "3m ago", "2h ago", "3d ago".
    static func age(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date)) / 60
        switch minutes {
        case ..<1: return "just now"
        case ..<60: return "\(minutes)m ago"
        case ..<(24 * 60): return "\(minutes / 60)h ago"
        default: return "\(minutes / (24 * 60))d ago"
        }
    }

    /// The account label with the identity swapped for a placeholder, plan
    /// kept: "user@domain (Max)", "ghuser (Business)".
    static func redacted(_ label: String, provider: Provider) -> String {
        let placeholder = provider == .copilot ? "ghuser" : "user@domain"
        let rest = label.split(separator: " ", maxSplits: 1).dropFirst().joined()
        return rest.isEmpty ? placeholder : "\(placeholder) \(rest)"
    }

    static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    /// Green until 70 % used, orange until 90 %, then red.
    static func tint(_ percent: Double) -> Color {
        switch percent {
        case ..<70: .green
        case ..<90: .orange
        default: .red
        }
    }
}
