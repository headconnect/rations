import AppKit
import SwiftUI

public enum RationsApp {
    @MainActor public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

/// Status item with a SwiftUI label (MenuBarExtra only renders text and images,
/// not the usage bars) and a popover for the details.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AccountStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let updates = UpdateChecker()
    /// Lazy only because it needs the store; created at launch.
    private lazy var hub = UsageHub(store: store)
    /// Pinned to the button's trailing edge, which stays put when the label
    /// changes width, so the popover does not move with it.
    private let anchor = PassthroughView()
    private var windowObservers: [NSObjectProtocol] = []
    /// Created on first use; closing hides it (`isReleasedWhenClosed` off) so
    /// the account rows keep their state between visits.
    private lazy var settingsWindow = SettingsWindow.make(store: store, hub: hub)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        _ = hub
        guard let button = statusItem.button else { return }
        let label = PassthroughHostingView(rootView: MenuBarLabel(store: store) { [statusItem] width in
            statusItem.length = width
        })
        label.translatesAutoresizingMaskIntoConstraints = false
        anchor.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        button.addSubview(anchor)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            label.topAnchor.constraint(equalTo: button.topAnchor),
            label.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            anchor.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            anchor.topAnchor.constraint(equalTo: button.topAnchor),
            anchor.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            anchor.widthAnchor.constraint(equalToConstant: 24),
        ])
        button.target = self
        button.action = #selector(togglePopover)

        let content = NSHostingController(rootView: PopoverView(store: store, updates: updates) { [weak self] in
            self?.openSettings()
        })
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        popover.behavior = .transient
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            observeStatusWindow()
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// The settings live in a window of their own: the popover is transient and
    /// too narrow for a list of accounts that keeps growing.
    private func openSettings() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    /// Accessory apps (LSUIElement) have no menu bar of their own, but macOS
    /// still resolves Cmd+C/V/X/A in text fields through the app's Edit menu.
    /// Without one, those shortcuts silently do nothing (right-click paste
    /// still works since it doesn't go through the menu). Cmd+W closes the
    /// settings window the same way.
    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll), keyEquivalent: "a")
        for menu in [fileMenu, editMenu] {
            let item = NSMenuItem()
            item.submenu = menu
            mainMenu.addItem(item)
        }
        return mainMenu
    }

    /// The popover follows the status item's window when it is resized but not
    /// when the menu bar then shifts it to keep the right edge in place, so it
    /// is re-anchored after both.
    private func observeStatusWindow() {
        guard windowObservers.isEmpty, let window = statusItem.button?.window else { return }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.popover.isShown else { return }
                    self.popover.show(relativeTo: self.anchor.bounds, of: self.anchor, preferredEdge: .minY)
                }
            })
        }
    }
}

// Both let clicks fall through to the status bar button underneath.

private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
