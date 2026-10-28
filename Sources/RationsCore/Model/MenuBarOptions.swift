import Foundation

/// Which parts of a menu bar gauge to draw. An account without its own copy
/// follows the global settings, so changing those still moves it.
struct MenuBarOptions: Codable, Equatable {
    var bars = true
    var percent = true
    var session = true
    var weekly = true
    var sessionCountdown = false
    var weeklyCountdown = false

    enum CodingKeys: String, CodingKey {
        case bars, percent, session, weekly, sessionCountdown, weeklyCountdown
    }

    /// Missing display toggles default to on, countdowns to off, matching
    /// the `@AppStorage` defaults in the settings UI.
    static func global(_ defaults: UserDefaults = .standard) -> MenuBarOptions {
        MenuBarOptions(
            bars: defaults.flag(Settings.menuBarBars),
            percent: defaults.flag(Settings.menuBarPercent),
            session: defaults.flag(Settings.menuBarSession),
            weekly: defaults.flag(Settings.menuBarWeekly),
            sessionCountdown: defaults.bool(forKey: Settings.menuBarSessionCountdown),
            weeklyCountdown: defaults.bool(forKey: Settings.menuBarWeeklyCountdown)
        )
    }

    func selectedWindows(in snapshot: UsageSnapshot) -> [UsageWindow] {
        snapshot.headline.filter {
            switch $0.menuBarRole {
            case .session: session
            case .weekly: weekly
            case .quota: true
            case nil: false
            }
        }
    }

    /// A pinned window was chosen by hand, so the session/weekly toggles do
    /// not apply and only its term picks the countdown preference.
    func showsCountdown(for window: UsageWindow, pinned: Bool = false) -> Bool {
        guard percent, window.percentUsed >= 100, window.resetsAt != nil else { return false }
        if pinned { return window.term == .short ? sessionCountdown : weeklyCountdown }
        switch window.menuBarRole {
        case .session: return session && sessionCountdown
        case .weekly: return weekly && weeklyCountdown
        case .quota: return weeklyCountdown
        case nil: return false
        }
    }

    static func resolve(for account: Account, global: MenuBarOptions) -> MenuBarOptions {
        (account.menuBar ?? global).paired
    }

    /// At least one of bars/percent and one of session/weekly, so a gauge is
    /// never blank. The UI disables the last toggle of a pair, but stored or
    /// hand-edited defaults can still be all off.
    var paired: MenuBarOptions {
        var options = self
        if !bars, !percent { options.bars = true; options.percent = true }
        if !session, !weekly { options.session = true; options.weekly = true }
        return options
    }
}

extension MenuBarOptions {
    /// Older account overrides have only the original four toggles.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bars = try values.decodeIfPresent(Bool.self, forKey: .bars) ?? true
        percent = try values.decodeIfPresent(Bool.self, forKey: .percent) ?? true
        session = try values.decodeIfPresent(Bool.self, forKey: .session) ?? true
        weekly = try values.decodeIfPresent(Bool.self, forKey: .weekly) ?? true
        sessionCountdown = try values.decodeIfPresent(Bool.self, forKey: .sessionCountdown) ?? false
        weeklyCountdown = try values.decodeIfPresent(Bool.self, forKey: .weeklyCountdown) ?? false
    }
}

private extension UserDefaults {
    func flag(_ key: String) -> Bool { object(forKey: key) == nil || bool(forKey: key) }
}
