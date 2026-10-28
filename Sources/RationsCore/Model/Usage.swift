import Foundation

/// One rate-limit window, e.g. the 5-hour session or the weekly cap.
struct UsageWindow: Equatable, Identifiable {
    enum MenuBarRole { case session, weekly, quota }
    /// Which countdown preference a pinned window follows: the 5-hour kind or
    /// the weekly/monthly kind.
    enum Term { case short, long }

    let id: String
    let label: String
    /// 0...100
    let percentUsed: Double
    let resetsAt: Date?
    /// Optional caption, e.g. "8,151 of 10,000 left".
    let detail: String?
    /// nil keeps model-specific and extra usage limits in the popover only.
    let menuBarRole: MenuBarRole?
    let term: Term

    /// `term` defaults from the role: sessions are short, everything else long.
    init(id: String, label: String, percentUsed: Double, resetsAt: Date?, detail: String? = nil,
         menuBarRole: MenuBarRole? = nil, term: Term? = nil) {
        self.id = id
        self.label = label
        self.detail = detail
        self.menuBarRole = menuBarRole
        self.term = term ?? (menuBarRole == .session ? .short : .long)
        self.percentUsed = min(max(percentUsed, 0), 100)
        // Whole seconds, so a countdown does not wobble on sub-second jitter.
        self.resetsAt = resetsAt.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.down)) }
    }
}

struct UsageSnapshot: Equatable {
    let windows: [UsageWindow]
    let fetchedAt: Date
    /// The provider's response body as received, which the usage hub hands to
    /// T3 Code unchanged. nil for providers the hub does not serve.
    var raw: Data? = nil

    /// The short-term and long-term limits, e.g. the 5-hour session and the
    /// weekly cap; per-model and overage windows are left to the popover.
    var headline: ArraySlice<UsageWindow> { windows.filter { $0.menuBarRole != nil }.prefix(2) }

    var earliestReset: Date? { windows.compactMap(\.resetsAt).min() }

    /// True if any limit's usage moved since `previous`.
    ///
    /// Identity and usage only. `resetsAt` is deliberately excluded: the Claude
    /// API recomputes it per request with a few ms of forward drift per second,
    /// so it crosses a whole second every couple of minutes even when nothing
    /// is happening. Comparing whole windows therefore saw a change on almost
    /// every poll, which pinned the interval to `RefreshPolicy.boost` and
    /// defeated the backoff.
    func hasChanges(since previous: UsageSnapshot?) -> Bool {
        guard let previous, windows.count == previous.windows.count else { return true }
        return zip(windows, previous.windows).contains {
            $0.id != $1.id || $0.percentUsed != $1.percentUsed || $0.detail != $1.detail
        }
    }
}
