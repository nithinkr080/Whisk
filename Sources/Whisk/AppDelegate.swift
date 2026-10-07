import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeys = HotKeyManager()
    private let permissions = PermissionState.shared
    private var statusItem: NSStatusItem?
    private var prefsWindow: NSWindow?
    private var permissionsWindow: NSWindow?
    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu-bar utility with no windows is a prime App Nap candidate; napping delays timers and redraws,
        // which makes the switcher panel show up late or not at all after the app has been idle.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical, .automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Whisk listens for the window-switching shortcut")
        permissions.refresh()
        if !permissions.allGranted { showPermissions() }

        let settings = Settings.shared
        settings.$showMenuBarIcon.receive(on: RunLoop.main).sink { [weak self] in self?.setMenuBarIcon(visible: $0) }.store(in: &cancellables)
        settings.$triggerModifier.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.hotKeys.applySystemShortcutOverrides() }.store(in: &cancellables)

        installHotKeysIfPossible()
        // Keep checking: the user grants permissions while the app is already running.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.restoreSystemShortcuts()
    }

    /// Launching the app again (e.g. from Finder) opens Preferences — handy when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferences()
        return true
    }

    private func poll() {
        let before = permissions.allGranted
        permissions.refresh()
        installHotKeysIfPossible()
        if !before, permissions.allGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.permissionsWindow?.close() }
        }
    }

    private func installHotKeysIfPossible() {
        guard !hotKeys.isInstalled, AXIsProcessTrusted() else { return }
        if hotKeys.install() { hotKeys.applySystemShortcutOverrides() }
    }

    // MARK: Menu bar

    private func setMenuBarIcon(visible: Bool) {
        if !visible {
            if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Whisk")
        let menu = NSMenu()
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Permissions…", action: #selector(openPermissions), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Whisk", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func openPreferences() { showPreferences() }
    @objc private func openPermissions() { showPermissions() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Windows

    private func showPreferences() {
        if prefsWindow == nil { prefsWindow = makePreferencesWindow() }
        present(prefsWindow!)
    }

    private func showPermissions() {
        if permissionsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: PermissionsView()))
            w.title = "Whisk Setup"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            permissionsWindow = w
        }
        present(permissionsWindow!)
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
