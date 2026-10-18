import Foundation

/// UserDefaults keys and defaults; read with `@AppStorage(Settings.x, ...)`.
enum Settings {
    static let menuBarBars = "menuBar.bars"          // Bool, true
    static let menuBarPercent = "menuBar.percent"    // Bool, true
    static let menuBarSession = "menuBar.session"    // Bool, true
    static let menuBarWeekly = "menuBar.weekly"      // Bool, true
    static let menuBarSessionCountdown = "menuBar.sessionCountdown" // Bool, false
    static let menuBarWeeklyCountdown = "menuBar.weeklyCountdown"   // Bool, false; monthly for Copilot
    static let popoverOpacity = "popover.opacity"    // Double, 0.75
    static let checkForUpdates = "updates.check"     // Bool, false
    static let accounts = "accounts"                 // Data, JSON [Account] in display order
    static let hubEnabled = "hub.enabled"            // Bool, false
    static let hubPort = "hub.port"                  // Int, 8318
    /// Bool, false. Not in the UI: launch with `-redactAccountLabels YES` to
    /// show placeholders instead of the signed-in identities, for screenshots.
    static let redactAccountLabels = "redactAccountLabels"

    static let defaultPopoverOpacity = 0.75
    static let minPopoverOpacity = 0.3
    /// Next to CLIProxyAPI's own 8317, so both can run on one machine.
    static let defaultHubPort = 8318
}
