import AppKit
import ServiceManagement
import SwiftUI

/// The settings window: a toolbar tab per area, like System Settings panes of
/// old. Accounts (list and per-account detail), the menu bar defaults every
/// account without its own overrides follows, general app settings, the usage
/// hub, and about. Every tab has the same size, so switching tabs never
/// resizes or moves the window.
enum SettingsWindow {
    @MainActor
    static func make(store: AccountStore, hub: UsageHub) -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction]
        tabs.addTabViewItem(item("Accounts", symbol: "person.2", AccountsSettings(store: store)))
        tabs.addTabViewItem(item("Menu Bar", symbol: "menubar.rectangle", MenuBarSettings()))
        tabs.addTabViewItem(item("General", symbol: "gearshape", GeneralSettings()))
        tabs.addTabViewItem(item("Usage Hub", symbol: "point.3.connected.trianglepath.dotted", UsageHubSettings(hub: hub)))
        tabs.addTabViewItem(item("About", symbol: "info.circle", AboutSettings()))
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    @MainActor
    private static func item(_ label: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = .preferredContentSize
        // The tab controller shows the selected tab's title as the window's.
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

/// Size of every tab, Accounts' list and detail included.
let settingsPaneSize = CGSize(width: 640, height: 560)

/// The defaults for every account that does not customise its menu bar.
struct MenuBarSettings: View {
    @AppStorage(Settings.menuBarBars) private var showBars = true
    @AppStorage(Settings.menuBarPercent) private var showPercent = true
    @AppStorage(Settings.menuBarSession) private var showSession = true
    @AppStorage(Settings.menuBarWeekly) private var showWeekly = true
    @AppStorage(Settings.menuBarSessionCountdown) private var sessionCountdown = false
    @AppStorage(Settings.menuBarWeeklyCountdown) private var weeklyCountdown = false

    var body: some View {
        Form {
            MenuBarOptionToggles(bars: $showBars, percent: $showPercent, session: $showSession, weekly: $showWeekly,
                                 sessionCountdown: $sessionCountdown, weeklyCountdown: $weeklyCountdown)
            Section {} footer: {
                Text("Accounts follow these unless they customise their menu bar under Accounts.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .settingsPane()
    }
}

struct GeneralSettings: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(Settings.popoverOpacity) private var opacity = Settings.defaultPopoverOpacity
    @AppStorage(Settings.checkForUpdates) private var checkForUpdates = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                Toggle(isOn: $checkForUpdates) {
                    Text("Check for updates")
                    Text("Polls GitHub every 6 hours")
                }
            }
            Section("Popover") {
                LabeledContent("Opacity") {
                    HStack {
                        Slider(value: $opacity, in: Settings.minPopoverOpacity...1).controlSize(.small)
                        Text("\(Int((opacity * 100).rounded())) %")
                            .monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .settingsPane()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// What Rations is, which version is running, and where it lives.
struct AboutSettings: View {
    private static let repository = URL(string: "https://github.com/headconnect/rations")!

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Rations").font(.title2.weight(.semibold))
                        Text("Version \(UpdateChecker.currentVersion)").foregroundStyle(.secondary).textSelection(.enabled)
                        Text("Claude, Codex, Copilot and Antigravity plan usage in the menu bar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Links") {
                link("Source code on GitHub", path: "")
                link("Release notes", path: "/releases")
                link("Report an issue", path: "/issues")
                link("Security policy", path: "/blob/main/SECURITY.md")
            }
            Section {} footer: {
                Text("Open source under the MIT licence.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .settingsPane()
    }

    private func link(_ title: String, path: String) -> some View {
        Link(destination: Self.repository.appendingPathComponent(path)) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
    }
}

extension View {
    /// A grouped form filling the fixed pane size, top-aligned, scrolling only
    /// if it ever outgrows it.
    func settingsPane() -> some View {
        formStyle(.grouped)
            .frame(width: settingsPaneSize.width, height: settingsPaneSize.height, alignment: .top)
    }
}

/// Form sections for one set of menu bar options. At least one display style
/// and one limit stay enabled. Copilot always shows its monthly quota and uses
/// the long-term countdown preference; pinned gauges choose their limits
/// themselves, so the limit toggles are left out for them.
struct MenuBarOptionToggles: View {
    @Binding var bars: Bool
    @Binding var percent: Bool
    @Binding var session: Bool
    @Binding var weekly: Bool
    @Binding var sessionCountdown: Bool
    @Binding var weeklyCountdown: Bool
    var provider: Provider? = nil
    var pinned = false

    private var hasSession: Bool { provider != .copilot }

    var body: some View {
        Section("Show") {
            Toggle("Bars", isOn: $bars).disabled(!percent)
            Toggle("Percentages", isOn: $percent).disabled(!bars)
        }
        if hasSession && !pinned {
            Section("Limits") {
                Toggle("Session (5-hour)", isOn: $session).disabled(!weekly)
                Toggle(provider == nil ? "Weekly / monthly" : "Weekly", isOn: $weekly).disabled(!session)
            }
        }
        Section {
            if hasSession {
                Toggle("Session", isOn: $sessionCountdown).disabled(!percent || (!pinned && !session))
            }
            Toggle(provider == .copilot ? "Monthly quota" : provider == nil ? "Weekly / monthly" : "Weekly",
                   isOn: $weeklyCountdown)
                .disabled(!percent || (hasSession && provider != nil && !pinned && !weekly))
        } header: {
            Text("At 100 %, show time until reset")
        }
    }
}
