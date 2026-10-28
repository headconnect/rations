import SwiftUI

/// "A ▤ 12%/4%  O ▤ 77%/47%  G ▤ 18%": per signed-in account, its tag, a
/// mini bar per limit window and the percentages, short-term window first.
/// Which parts appear is a user setting; an account with several gauges gets
/// one such entry per gauge, with any spacers it has between them.
struct MenuBarLabel: View {
    let store: AccountStore
    /// Called with the rendered width so the status item can follow it.
    let onWidthChange: (CGFloat) -> Void

    var body: some View {
        let active = store.monitors.filter(\.isSignedIn)
        HStack(spacing: 10) {
            if active.isEmpty {
                Text("Rations")
            } else {
                ForEach(active) { AccountGauges(monitor: $0) }
            }
        }
        .font(.system(size: 12).monospacedDigit())
        .padding(.horizontal, 7)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onWidthChange($0) }
    }
}

/// Several views, so they space out like separate accounts in the parent HStack.
private struct AccountGauges: View {
    let monitor: AccountMonitor
    @AppStorage(Settings.menuBarBars) private var showBars = true
    @AppStorage(Settings.menuBarPercent) private var showPercent = true
    @AppStorage(Settings.menuBarSession) private var showSession = true
    @AppStorage(Settings.menuBarWeekly) private var showWeekly = true
    @AppStorage(Settings.menuBarSessionCountdown) private var sessionCountdown = false
    @AppStorage(Settings.menuBarWeeklyCountdown) private var weeklyCountdown = false

    var body: some View {
        let options = MenuBarOptions.resolve(
            for: monitor.account,
            global: MenuBarOptions(bars: showBars, percent: showPercent, session: showSession, weekly: showWeekly,
                                   sessionCountdown: sessionCountdown, weeklyCountdown: weeklyCountdown)
        )
        ForEach(Gauge.resolve(monitor.account, snapshot: monitor.snapshot, options: options)) { gauge in
            if let spacer = gauge.spacer {
                SpacerView(spacer: spacer)
            } else {
                GaugeView(account: monitor.account, gauge: gauge, options: options)
            }
        }
    }
}

private struct GaugeView: View {
    let account: Account
    let gauge: Gauge.Resolved
    let options: MenuBarOptions

    var body: some View {
        HStack(spacing: 4) {
            if let data = gauge.image, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(height: 14)
            } else if let tag = gauge.tag {
                Text(tag).fontWeight(.semibold)
            } else {
                AccountLabel(account: account, height: 14)
            }
            let windows = gauge.windows
            if windows.isEmpty {
                Text("–")
            } else {
                if options.bars {
                    VStack(spacing: 2) {
                        ForEach(windows) { MiniBar(percent: $0.percentUsed) }
                    }
                }
                if options.percent {
                    if windows.contains(where: { options.showsCountdown(for: $0, pinned: gauge.pinned) }) {
                        // Local redraws only; the account's network schedule is unchanged.
                        TimelineView(.everyMinute) { context in
                            values(windows, options: options, now: context.date)
                        }
                    } else {
                        values(windows, options: options, now: .now)
                    }
                }
            }
        }
    }

    private func values(_ windows: [UsageWindow], options: MenuBarOptions, now: Date) -> some View {
        Text(windows.map { Format.menuBarValue($0, options: options, pinned: gauge.pinned, now: now) }.joined(separator: "/"))
    }
}

/// A separator such as "|" in the secondary colour, an image at icon height,
/// or with empty text nothing but the gap around it.
struct SpacerView: View {
    let spacer: Gauge.Spacer
    var height: CGFloat = 14

    var body: some View {
        if let data = spacer.image, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit().frame(height: height)
        } else if spacer.text.isEmpty {
            Color.clear.frame(width: 1, height: 1)
        } else {
            Text(spacer.text).foregroundStyle(.secondary)
        }
    }
}

private struct MiniBar: View {
    let percent: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.primary.opacity(0.25))
            Capsule().fill(Format.tint(percent)).frame(width: max(3, 14 * percent / 100))
        }
        .frame(width: 14, height: 3.5)
    }
}
