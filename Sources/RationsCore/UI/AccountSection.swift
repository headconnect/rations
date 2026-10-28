import SwiftUI

struct AccountSection: View {
    let monitor: AccountMonitor
    /// Only for the store-wide sign-in guard: one browser flow at a time.
    let store: AccountStore
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if monitor.isSignedIn {
                usage
            } else {
                signIn
            }
            if case .error(let message) = monitor.status {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            AccountLabel(account: monitor.account).font(.headline)
            Text(monitor.provider.name).font(.headline)
            let subtitle = [monitor.account.name, monitor.identity].filter { !$0.isEmpty }.joined(separator: " · ")
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if monitor.isSignedIn {
                Button { monitor.refreshNow() } label: {
                    if monitor.status == .refreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
                Button { monitor.signOut() } label: { Image(systemName: "rectangle.portrait.and.arrow.right") }
                    .buttonStyle(.borderless)
                    .help("Sign out")
            }
        }
    }

    @ViewBuilder
    private var usage: some View {
        if let snapshot = monitor.snapshot {
            ForEach(snapshot.windows) { window in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(window.label)
                        Spacer()
                        Text("\(Format.percent(window.percentUsed)) used").monospacedDigit()
                    }
                    .font(.callout)
                    ProgressView(value: window.percentUsed, total: 100)
                        .tint(Format.tint(window.percentUsed))
                    let caption = [window.resetsAt.map { "Resets in \(Format.countdown(to: $0, from: now))" }, window.detail]
                        .compactMap { $0 }.joined(separator: " · ")
                    if !caption.isEmpty {
                        Text(caption).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Text(schedule(snapshot)).font(.caption2).foregroundStyle(.tertiary)
        } else if monitor.status == .refreshing {
            Text("Loading…").font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var signIn: some View {
        if let pending = monitor.pendingSignIn {
            SignInPending(monitor: monitor, pending: pending)
        } else {
            SignInButton(monitor: monitor, store: store)
        }
    }


    private func schedule(_ snapshot: UsageSnapshot) -> String {
        var parts = ["Updated \(Format.age(snapshot.fetchedAt, now: now))"]
        if let next = monitor.nextCheck, next > now {
            parts.append("next check in \(Format.countdown(to: next, from: now))")
        }
        return parts.joined(separator: " · ")
    }

}

extension AccountMonitor {
    /// Who is signed in, as reported by the provider; a placeholder under the
    /// screenshot flag (see `Settings.redactAccountLabels`).
    var identity: String {
        guard let label = tokens?.account else { return "" }
        guard UserDefaults.standard.bool(forKey: Settings.redactAccountLabels) else { return label }
        return Format.redacted(label, provider: provider)
    }
}
