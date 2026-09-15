// Minimal check runner: `swift run RationsChecks`. Exits non-zero on failure.
// `--live` additionally fetches usage for every signed-in account and prints it.
import AppKit
import Foundation
@testable import RationsCore

var failures = 0

func check(_ label: String, _ body: () throws -> Bool) {
    do {
        if try body() {
            print("ok   \(label)")
            return
        }
        print("FAIL \(label)")
    } catch {
        print("FAIL \(label): \(error)")
    }
    failures += 1
}

// MARK: RefreshPolicy

check("policy starts at base") { RefreshPolicy().interval == 5 * 60 }

check("change boosts to 2 min") {
    var policy = RefreshPolicy()
    policy.record(changed: true)
    return policy.interval == 2 * 60
}

check("unchanged backs off 5 → 10 → 20 → 20") {
    var policy = RefreshPolicy()
    policy.record(changed: true)
    var intervals: [TimeInterval] = []
    for _ in 0..<4 {
        policy.record(changed: false)
        intervals.append(policy.interval)
    }
    return intervals == [300, 600, 1200, 1200]
}

check("rate limit backoff is marked, success clears it") {
    var policy = RefreshPolicy()
    policy.backOff()
    guard policy.isBackingOff else { return false }
    policy.record(changed: false)
    return !policy.isBackingOff
}

check("reset returns to base") {
    var policy = RefreshPolicy()
    policy.backOff()
    policy.reset()
    return policy.interval == 5 * 60
}

// MARK: Change detection

/// The Claude API recomputes resets_at per request with a few ms of forward
/// drift per second, so it straddles whole seconds every couple of minutes.
/// Counting that as a change pinned the poll interval to boost forever.
check("drifting reset time alone is not a change") {
    let earlier = UsageSnapshot(windows: [
        UsageWindow(id: "five_hour", label: "Session (5h)", percentUsed: 16,
                    resetsAt: ISO8601.date("2026-09-10T10:39:59.891656+00:00")),
    ], fetchedAt: .now)
    let later = UsageSnapshot(windows: [
        UsageWindow(id: "five_hour", label: "Session (5h)", percentUsed: 16,
                    resetsAt: ISO8601.date("2026-09-10T10:40:00.192184+00:00")),
    ], fetchedAt: .now)
    return !later.hasChanges(since: earlier)
}

check("moved usage is a change") {
    let earlier = UsageSnapshot(windows: [
        UsageWindow(id: "five_hour", label: "Session (5h)", percentUsed: 16, resetsAt: nil),
    ], fetchedAt: .now)
    let later = UsageSnapshot(windows: [
        UsageWindow(id: "five_hour", label: "Session (5h)", percentUsed: 17, resetsAt: nil),
    ], fetchedAt: .now)
    return later.hasChanges(since: earlier)
}

check("a changed detail counts even at the same percent") {
    let earlier = UsageSnapshot(windows: [
        UsageWindow(id: "chat", label: "Chat", percentUsed: 19, resetsAt: nil, detail: "8,151 of 10,000 left"),
    ], fetchedAt: .now)
    let later = UsageSnapshot(windows: [
        UsageWindow(id: "chat", label: "Chat", percentUsed: 19, resetsAt: nil, detail: "8,140 of 10,000 left"),
    ], fetchedAt: .now)
    return later.hasChanges(since: earlier)
}

check("an added or renamed window is a change") {
    let one = UsageSnapshot(windows: [
        UsageWindow(id: "five_hour", label: "Session (5h)", percentUsed: 16, resetsAt: nil),
    ], fetchedAt: .now)
    let two = UsageSnapshot(windows: one.windows + [
        UsageWindow(id: "seven_day", label: "Weekly", percentUsed: 66, resetsAt: nil),
    ], fetchedAt: .now)
    let renamed = UsageSnapshot(windows: [
        UsageWindow(id: "session", label: "Session (5h)", percentUsed: 16, resetsAt: nil),
    ], fetchedAt: .now)
    return two.hasChanges(since: one) && one.hasChanges(since: two) && renamed.hasChanges(since: one)
}

// MARK: Parsing

check("claude usage windows") {
    let json = """
    {
      "five_hour": {"utilization": 1.0, "resets_at": "2026-09-06T11:30:00.144211+00:00", "limit_dollars": null},
      "seven_day": {"utilization": 2.0, "resets_at": "2026-09-12T17:00:00+00:00"},
      "seven_day_opus": null,
      "nimbus_quill": {"utilization": 0.0, "resets_at": null},
      "extra_usage": {"is_enabled": false, "utilization": 67.7},
      "limits": [{"kind": "session", "percent": 1}],
      "spend": {"percent": 68, "enabled": false},
      "member_dashboard_available": false
    }
    """
    let windows = try JSONDecoder.apiRawKeys.decode(ClaudeUsage.self, from: Data(json.utf8)).windows()
    let ids: [String] = windows.map(\.id)
    let percents: [Double] = windows.map(\.percentUsed)
    return ids == ["five_hour", "seven_day"] && percents == [1, 2]
        && windows[0].resetsAt?.timeIntervalSince1970 == 1_788_694_200
}

check("claude extra usage shown when enabled") {
    let json = #"{"five_hour": {"utilization": 5.0}, "extra_usage": {"is_enabled": true, "utilization": 40.0}}"#
    let windows = try JSONDecoder.apiRawKeys.decode(ClaudeUsage.self, from: Data(json.utf8)).windows()
    return windows.map(\.id) == ["five_hour", "extra_usage"]
}

check("claude reads the named Fable allowance from the live response shape") {
    let json = """
    {
      "five_hour": {"utilization": 17, "resets_at": "2026-09-09T16:49:59+00:00"},
      "seven_day": {"utilization": 59, "resets_at": "2026-09-12T16:59:59+00:00"},
      "nimbus_quill": {"utilization": 0, "resets_at": null},
      "limits": [
        {"kind": "session", "percent": 17, "scope": null},
        {"kind": "weekly_all", "percent": 59, "scope": null},
        {"kind": "weekly_scoped", "percent": 94, "resets_at": "2026-09-12T16:59:59.769611+00:00",
         "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": true}
      ]
    }
    """
    let windows = try JSONDecoder.apiRawKeys.decode(ClaudeUsage.self, from: Data(json.utf8)).windows()
    let snapshot = UsageSnapshot(windows: windows, fetchedAt: .now)
    return windows.map(\.label) == ["Session (5h)", "Weekly · all models", "Weekly · Fable"]
        && windows.last?.percentUsed == 94 && windows.last?.resetsAt == windows[1].resetsAt
        && snapshot.headline.map(\.id) == ["five_hour", "seven_day"]
}

check("Fable stays popover-only with missing headline windows and no reset") {
    let json = #"{"seven_day": {"utilization": 59}, "limits": [{"kind": "weekly_scoped", "percent": 0, "scope": {"model": {"display_name": "Fable"}}}]}"#
    let windows = try JSONDecoder.apiRawKeys.decode(ClaudeUsage.self, from: Data(json.utf8)).windows()
    let snapshot = UsageSnapshot(windows: windows, fetchedAt: .now)
    return windows.last?.label == "Weekly · Fable" && windows.last?.percentUsed == 0
        && snapshot.headline.map(\.id) == ["seven_day"]
        && MenuBarOptions(session: false).selectedWindows(in: snapshot).map(\.id) == ["seven_day"]
        && MenuBarOptions(weekly: false).selectedWindows(in: snapshot).isEmpty
}

check("named Fable limit wins over legacy data and ignores malformed entries") {
    let json = #"{"seven_day_overage_included": {"utilization": 80}, "limits": [null, 42, {"kind": "weekly_scoped", "percent": "bad"}, {"kind": "weekly_scoped", "percent": 94, "scope": {"model": {"display_name": "Fable"}}}]}"#
    let windows = try JSONDecoder.apiRawKeys.decode(ClaudeUsage.self, from: Data(json.utf8)).windows()
    return windows.count == 1 && windows[0].label == "Weekly · Fable" && windows[0].percentUsed == 94
        && UsageSnapshot(windows: windows, fetchedAt: .now).headline.isEmpty
}

check("Fable matches Claude's usage page even when is_active is false") {
    let json = """
    {
      "five_hour": {"utilization": 13, "resets_at": "2026-09-15T18:10:00+00:00"},
      "seven_day": {"utilization": 5, "resets_at": "2026-09-19T17:00:00+00:00"},
      "limits": [
        {"kind": "session", "percent": 13, "is_active": true},
        {"kind": "weekly_all", "percent": 5, "is_active": false},
        {"kind": "weekly_scoped", "percent": 2, "resets_at": "2026-09-19T17:00:00+00:00",
         "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
      ]
    }
    """
    let windows = try JSONDecoder.apiRawKeys.decode(ClaudeUsage.self, from: Data(json.utf8)).windows()
    return windows.map(\.label) == ["Session (5h)", "Weekly · all models", "Weekly · Fable"]
        && windows.map(\.percentUsed) == [13, 5, 2]
        && windows.last?.resetsAt == ISO8601.date("2026-09-19T17:00:00+00:00")
        && UsageSnapshot(windows: windows, fetchedAt: .now).headline.map(\.id) == ["five_hour", "seven_day"]
}

check("an inactive Fable allowance is still shown at zero usage") {
    let json = #"{"limits": [{"kind": "weekly_scoped", "percent": 0, "scope": {"model": {"display_name": "Fable"}}, "is_active": false}]}"#
    let windows = try JSONDecoder.apiRawKeys.decode(ClaudeUsage.self, from: Data(json.utf8)).windows()
    return windows.count == 1 && windows[0].label == "Weekly · Fable" && windows[0].percentUsed == 0
}

check("an inactive Fable record does not shadow the active allowance") {
    let json = #"{"limits": [{"kind": "weekly_scoped", "percent": 94, "scope": {"model": {"display_name": "Fable"}}, "is_active": false}, {"kind": "weekly_scoped", "percent": 25, "scope": {"model": {"display_name": "Fable"}}, "is_active": true}]}"#
    let windows = try JSONDecoder.apiRawKeys.decode(ClaudeUsage.self, from: Data(json.utf8)).windows()
    return windows.count == 1 && windows[0].label == "Weekly · Fable" && windows[0].percentUsed == 25
}

check("legacy Fable allowance has a friendly label without a reset") {
    let json = #"{"seven_day_overage_included": {"utilization": 25}, "limits": null}"#
    let windows = try JSONDecoder.apiRawKeys.decode(ClaudeUsage.self, from: Data(json.utf8)).windows()
    return windows.count == 1 && windows[0].label == "Weekly · Fable" && windows[0].percentUsed == 25
}

check("codex usage windows") {
    let json = """
    {
      "plan_type": "team",
      "rate_limit": {
        "allowed": true,
        "primary_window": {"used_percent": 77, "limit_window_seconds": 18000, "reset_after_seconds": 16181, "reset_at": 1788692687},
        "secondary_window": {"used_percent": 43, "limit_window_seconds": 604800, "reset_at": 1789213891}
      }
    }
    """
    let windows = try JSONDecoder.api.decode(CodexUsage.self, from: Data(json.utf8)).windows()
    let labels: [String] = windows.map(\.label)
    let percents: [Double] = windows.map(\.percentUsed)
    return labels == ["Session (5h)", "Weekly"] && percents == [77, 43]
        && windows[1].resetsAt?.timeIntervalSince1970 == 1_789_213_891
}

check("copilot usage windows skip unlimited quotas") {
    let json = """
    {
      "login": "octocat", "copilot_plan": "business", "quota_reset_date_utc": "2026-10-01T00:00:00.000Z",
      "quota_snapshots": {
        "chat": {"percent_remaining": 100.0, "unlimited": true, "entitlement": 0, "remaining": 0},
        "premium_interactions": {"percent_remaining": 81.5, "unlimited": false, "entitlement": 10000, "remaining": 8151, "overage_count": 0}
      }
    }
    """
    let windows = try JSONDecoder.api.decode(CopilotUsage.self, from: Data(json.utf8)).windows()
    return windows.count == 1 && windows[0].id == "premium_interactions" && windows[0].percentUsed == 18.5
        && windows[0].detail == "\(8151.formatted()) of \(10000.formatted()) left"  // locale-dependent grouping
        && windows[0].resetsAt?.timeIntervalSince1970 == 1_790_812_800
}

check("codex without rate limit") {
    try JSONDecoder.api.decode(CodexUsage.self, from: Data(#"{"rate_limit": null}"#.utf8)).windows().isEmpty
}

check("change detection ignores sub-second jitter") {
    let a = UsageWindow(id: "w", label: "W", percentUsed: 10, resetsAt: Date(timeIntervalSince1970: 100.2))
    let b = UsageWindow(id: "w", label: "W", percentUsed: 10, resetsAt: Date(timeIntervalSince1970: 100.9))
    let first = UsageSnapshot(windows: [a], fetchedAt: .now)
    let second = UsageSnapshot(windows: [b], fetchedAt: .now)
    return !second.hasChanges(since: first) && first.hasChanges(since: nil)
}

check("moving an account clamps at the ends") {
    let accounts = [Account(provider: .claude, tag: "A"), Account(provider: .codex, tag: "O"), Account(provider: .copilot, tag: "G")]
    return Account.moved(accounts, at: 2, by: -1).map(\.tag) == ["A", "G", "O"]
        && Account.moved(accounts, at: 0, by: -1).map(\.tag) == ["A", "O", "G"]
        && Account.moved(accounts, at: 1, by: 5).map(\.tag) == ["A", "G", "O"]
        && Account.moved(accounts, at: 7, by: 1).map(\.tag) == ["A", "O", "G"]
}

check("account icon is scaled to menu bar height") {
    let image = NSImage(size: NSSize(width: 100, height: 50), flipped: false) { rect in
        NSColor.red.setFill(); rect.fill(); return true
    }
    guard let data = AccountIcon.png(image), let rep = NSBitmapImageRep(data: data) else { return false }
    return rep.pixelsHigh == 32 && rep.pixelsWide == 64 && data.count < 2_000
}

// MARK: Auth helpers

check("pkce challenge matches RFC 7636 vector") {
    PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
}

check("jwt claims") {
    let payload = Data(#"{"exp": 1700000000, "email": "a@b.c"}"#.utf8).base64URLEncoded()
    let token = "eyJhbGciOiJub25lIn0.\(payload).sig"
    return JWT.claims(token)?["email"] as? String == "a@b.c"
        && JWT.expiry(token)?.timeIntervalSince1970 == 1_700_000_000
}

// MARK: Formatting

check("version comparison") {
    UpdateChecker.isNewer("1.1", than: "1.0.0") && UpdateChecker.isNewer("1.0.1", than: "1.0")
        && !UpdateChecker.isNewer("1.0.0", than: "1.0") && !UpdateChecker.isNewer("0.9.9", than: "1.0")
}

check("countdown formatting") {
    let now = Date(timeIntervalSince1970: 0)
    return Format.countdown(to: now.addingTimeInterval(16_181), from: now) == "4h 30m"
        && Format.countdown(to: now.addingTimeInterval(537_385), from: now) == "6d 5h"
        && Format.countdown(to: now.addingTimeInterval(90), from: now) == "2m"
        && Format.countdown(to: now, from: now) == "now"
}

check("menu bar countdown formatting at minute and day boundaries") {
    let now = Date(timeIntervalSince1970: 0)
    let cases: [(TimeInterval, String)] = [
        (4 * 3600 + 37 * 60, "04:37"), (3 * 86400 + 17 * 3600 + 29 * 60, "3d 17:29"),
        (86400, "1d 00:00"), (86399, "1d 00:00"), (86340, "23:59"),
        (60, "00:01"), (1, "00:01"), (0, "00:00"), (-60, "00:00")
    ]
    return cases.allSatisfy { Format.menuBarCountdown(to: now.addingTimeInterval($0.0), from: now) == $0.1 }
}

check("exhausted usage counts down between fetches and waits at zero after reset") {
    let now = Date(timeIntervalSince1970: 0)
    let window = UsageWindow(id: "five_hour", label: "Session", percentUsed: 100,
                             resetsAt: now.addingTimeInterval(4 * 3600 + 37 * 60), menuBarRole: .session)
    let options = MenuBarOptions(sessionCountdown: true)
    return Format.menuBarValue(window, options: options, now: now) == "04:37"
        && Format.menuBarValue(window, options: options, now: now.addingTimeInterval(60)) == "04:36"
        && Format.menuBarValue(window, options: options, now: now.addingTimeInterval(20 * 60)) == "04:17"
        && Format.menuBarValue(window, options: options, now: now.addingTimeInterval(6 * 3600)) == "00:00"
        && Format.menuBarValue(window, options: MenuBarOptions(), now: now) == "100%"
}

check("countdowns require exhaustion, a reset, and the matching enabled setting") {
    let reset = Date(timeIntervalSince1970: 10000)
    let session = UsageWindow(id: "five_hour", label: "Session", percentUsed: 100, resetsAt: reset, menuBarRole: .session)
    let weekly = UsageWindow(id: "seven_day", label: "Weekly", percentUsed: 100, resetsAt: reset, menuBarRole: .weekly)
    let almost = UsageWindow(id: "primary", label: "Session", percentUsed: 99.9, resetsAt: reset, menuBarRole: .session)
    let noReset = UsageWindow(id: "primary", label: "Session", percentUsed: 100, resetsAt: nil, menuBarRole: .session)
    let options = MenuBarOptions(sessionCountdown: true)
    return options.showsCountdown(for: session) && !options.showsCountdown(for: weekly)
        && !options.showsCountdown(for: almost) && !options.showsCountdown(for: noReset)
        && !MenuBarOptions(percent: false, sessionCountdown: true).showsCountdown(for: session)
        && !MenuBarOptions(session: false, sessionCountdown: true).showsCountdown(for: session)
        && MenuBarOptions(weeklyCountdown: true).showsCountdown(for: weekly)
        && !MenuBarOptions(weekly: false, weeklyCountdown: true).showsCountdown(for: weekly)
}

check("Copilot uses the long-term countdown regardless of session and weekly visibility") {
    let now = Date(timeIntervalSince1970: 0)
    let quota = UsageWindow(id: "premium_interactions", label: "Monthly", percentUsed: 100,
                            resetsAt: now.addingTimeInterval(3 * 86400 + 17 * 3600 + 29 * 60), menuBarRole: .quota)
    let snapshot = UsageSnapshot(windows: [quota], fetchedAt: now)
    let options = MenuBarOptions(session: false, weekly: false, weeklyCountdown: true)
    return options.selectedWindows(in: snapshot) == [quota]
        && Format.menuBarValue(quota, options: options, now: now) == "3d 17:29"
        && !MenuBarOptions(sessionCountdown: true).showsCountdown(for: quota)
}

check("age formatting") {
    let now = Date(timeIntervalSince1970: 1_000_000)
    return Format.age(now.addingTimeInterval(-20), now: now) == "just now"
        && Format.age(now.addingTimeInterval(-3 * 60), now: now) == "3m ago"
        && Format.age(now.addingTimeInterval(-90 * 60), now: now) == "1h ago"
        && Format.age(now.addingTimeInterval(-3 * 86_400 - 60), now: now) == "3d ago"
}

check("redacted account labels keep the plan") {
    Format.redacted("someone@example.com (Max)", provider: .claude) == "user@domain (Max)"
        && Format.redacted("someone@example.com", provider: .codex) == "user@domain"
        && Format.redacted("octocat (Business)", provider: .copilot) == "ghuser (Business)"
}

// MARK: Accounts

check("vault json is keyed by account id and round trips") {
    let id = UUID()
    let tokens = OAuthTokens(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 100),
                             account: "me@example.com", accountID: "acc")
    let data = try JSONEncoder().encode(TokenStore.Vault([id: tokens]))
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let decoded = try JSONDecoder().decode(TokenStore.Vault.self, from: data)
    return json?["version"] as? Int == 1
        && (json?["tokens"] as? [String: Any])?.keys.sorted() == [id.uuidString]
        && decoded.byAccount == [id: tokens]
}

check("vault drops entries that are not account ids") {
    let json = #"{"version": 1, "tokens": {"claude": {"accessToken": "a"}}}"#
    return try JSONDecoder().decode(TokenStore.Vault.self, from: Data(json.utf8)).byAccount.isEmpty
}

check("migration turns legacy items into tagged accounts") {
    let legacy: [LegacyMigration.Legacy] = [
        (provider: .claude, tokens: OAuthTokens(accessToken: "c", refreshToken: nil, expiresAt: nil, account: nil, accountID: nil)),
        (provider: .copilot, tokens: OAuthTokens(accessToken: "g", refreshToken: nil, expiresAt: nil, account: nil, accountID: nil)),
    ]
    let (accounts, vault) = LegacyMigration.fold(legacy)
    return accounts.map(\.provider) == [.claude, .copilot]
        && accounts.map(\.tag) == ["A", "G"]
        && vault[accounts[0].id]?.accessToken == "c"
        && vault[accounts[1].id]?.accessToken == "g"
        && LegacyMigration.fold([]).accounts.isEmpty
}

check("tag is trimmed, capped at three clusters and falls back") {
    Account.normalized(tag: "  hi  ", provider: .claude) == "hi"
        && Account.normalized(tag: "abcde", provider: .claude) == "abc"
        && Account.normalized(tag: "   ", provider: .codex) == "O"
        && Account.normalized(tag: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}x", provider: .claude).count == 2
}

check("second account of a provider is numbered") {
    let first = Account(provider: .claude, tag: Account.defaultTag(for: .claude, existing: []))
    let second = Account(provider: .claude, tag: Account.defaultTag(for: .claude, existing: [first]))
    return first.tag == "A" && second.tag == "A2"
        && Account.defaultTag(for: .claude, existing: [second]) == "A"
        && Account.defaultTag(for: .codex, existing: [first, second]) == "O"
}

check("menu bar options follow the globals unless overridden") {
    let globals = MenuBarOptions(bars: false, percent: true, session: true, weekly: false, sessionCountdown: true)
    var account = Account(provider: .claude, tag: "A")
    let followed = MenuBarOptions.resolve(for: account, global: globals)
    account.menuBar = MenuBarOptions(bars: true, percent: false, session: false, weekly: true)
    return followed == globals && MenuBarOptions.resolve(for: account, global: globals) == account.menuBar
}

check("old account overrides decode without losing accounts or enabling countdowns") {
    let json = #"[{"id":"00000000-0000-0000-0000-000000000001","provider":"claude","tag":"A","name":"Office","menuBar":{"bars":false,"percent":true,"session":false,"weekly":true}}]"#
    let accounts = try JSONDecoder().decode([Account].self, from: Data(json.utf8))
    return accounts.count == 1 && accounts[0].name == "Office"
        && accounts[0].menuBar == MenuBarOptions(bars: false, session: false)
}

check("countdown overrides persist and stay independent per account") {
    let globals = MenuBarOptions(sessionCountdown: true)
    let a = Account(provider: .claude, tag: "A", menuBar: MenuBarOptions(weeklyCountdown: true))
    let b = Account(provider: .claude, tag: "A2")
    let data = try JSONEncoder().encode([a, b])
    let accounts = try JSONDecoder().decode([Account].self, from: data)
    return accounts == [a, b]
        && MenuBarOptions.resolve(for: accounts[0], global: globals) == MenuBarOptions(weeklyCountdown: true)
        && MenuBarOptions.resolve(for: accounts[1], global: globals) == globals
}

check("menu bar options keep one of each pair") {
    MenuBarOptions(bars: false, percent: false, session: false, weekly: false).paired == MenuBarOptions()
        && !MenuBarOptions(bars: false, percent: true, session: true, weekly: true).paired.bars
}

check("global menu bar options default to on") {
    let suite = "no.enso.rations.checks"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let fresh = MenuBarOptions.global(defaults)
    defaults.set(false, forKey: Settings.menuBarWeekly)
    defaults.set(true, forKey: Settings.menuBarWeeklyCountdown)
    let edited = MenuBarOptions.global(defaults)
    defaults.removePersistentDomain(forName: suite)
    return fresh == MenuBarOptions() && !edited.weekly && edited.session
        && edited.weeklyCountdown && !edited.sessionCountdown
}

// MARK: Live (optional)

if CommandLine.arguments.contains("--live") {
    // Read-only on purpose: an AccountStore here would start polling loops that
    // refresh tokens and rewrite the vault behind the running app's back.
    let defaults = UserDefaults(suiteName: "no.enso.rations") ?? .standard
    let stored = defaults.data(forKey: Settings.accounts) ?? Data()
    let accounts = (try? JSONDecoder().decode([Account].self, from: stored)) ?? []
    let vault = accounts.isEmpty ? [:] : ((try? TokenStore.load()) ?? [:])
    for account in accounts {
        let label = "\(account.tag) \(account.provider.name)"
        guard let tokens = vault[account.id] else {
            print("--   \(label): not signed in")
            continue
        }
        do {
            let snapshot = try await account.provider.service.fetchUsage(tokens)
            let summary = snapshot.windows.map { window in
                let reset = window.resetsAt.map { " (resets in \(Format.countdown(to: $0, from: .now)))" } ?? ""
                return "\(window.label) \(Int(window.percentUsed.rounded()))%\(reset)"
            }
            print("ok   \(label) [\(tokens.account ?? "?")]: \(summary.joined(separator: ", "))")
        } catch {
            print("FAIL \(label): \(error.localizedDescription)")
            failures += 1
        }
    }
}

print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
