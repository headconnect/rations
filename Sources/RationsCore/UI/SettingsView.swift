import ServiceManagement
import SwiftUI

/// The settings window: accounts first, then the global menu bar defaults
/// (used by every account without its own overrides), then general, then the
/// usage hub.
struct SettingsView: View {
    static let width: CGFloat = 400

    let store: AccountStore
    let hub: UsageHub
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(Settings.menuBarBars) private var showBars = true
    @AppStorage(Settings.menuBarPercent) private var showPercent = true
    @AppStorage(Settings.menuBarSession) private var showSession = true
    @AppStorage(Settings.menuBarWeekly) private var showWeekly = true
    @AppStorage(Settings.menuBarSessionCountdown) private var sessionCountdown = false
    @AppStorage(Settings.menuBarWeeklyCountdown) private var weeklyCountdown = false
    @AppStorage(Settings.popoverOpacity) private var opacity = Settings.defaultPopoverOpacity
    @AppStorage(Settings.checkForUpdates) private var checkForUpdates = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Accounts")
            ForEach(store.monitors) { monitor in
                AccountSettingsRow(monitor: monitor, store: store)
            }
            AddAccountMenu(store: store)
            heading("Global Default Menu Bar Appearance").padding(.top, 4)
            MenuBarOptionToggles(bars: $showBars, percent: $showPercent, session: $showSession, weekly: $showWeekly,
                                 sessionCountdown: $sessionCountdown, weeklyCountdown: $weeklyCountdown)
            heading("General").padding(.top, 4)
            HStack {
                Text("Popover opacity")
                Slider(value: $opacity, in: Settings.minPopoverOpacity...1).controlSize(.small)
                Text("\(Int((opacity * 100).rounded())) %")
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            Toggle("Check for updates (polls GitHub every 6 hours)", isOn: $checkForUpdates)
            heading("Usage Hub").padding(.top, 4)
            UsageHubSettings(hub: hub)
        }
        .toggleStyle(.checkbox)
        .font(.callout)
        .padding(16)
        .frame(width: Self.width)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.caption).foregroundStyle(.secondary)
    }
}

/// At least one display style and one window stay enabled. Copilot always
/// shows its monthly quota and uses the long-term countdown preference.
struct MenuBarOptionToggles: View {
    @Binding var bars: Bool
    @Binding var percent: Bool
    @Binding var session: Bool
    @Binding var weekly: Bool
    @Binding var sessionCountdown: Bool
    @Binding var weeklyCountdown: Bool
    var provider: Provider? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Toggle("Bars", isOn: $bars).disabled(!percent)
                    if provider != .copilot {
                        Toggle("Session", isOn: $session).disabled(!weekly)
                    }
                }
                GridRow {
                    Toggle("Percentages", isOn: $percent).disabled(!bars)
                    if provider != .copilot {
                        Toggle("Weekly", isOn: $weekly).disabled(!session)
                    }
                }
            }
            Text("At 100%, show time until reset:").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                if provider != .copilot {
                    Toggle("Session", isOn: $sessionCountdown).disabled(!percent || !session)
                }
                Toggle(provider == .copilot ? "Monthly quota" : provider == nil ? "Weekly / monthly" : "Weekly",
                       isOn: $weeklyCountdown)
                    .disabled(!percent || (provider != .copilot && provider != nil && !weekly))
            }
        }
    }
}
