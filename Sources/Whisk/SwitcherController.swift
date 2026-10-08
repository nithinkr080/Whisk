import AppKit
import SwiftUI

final class SwitcherPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .screenSaver
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Follow the user to whichever Space (desktop or fullscreen app) is active each time the panel is ordered
        // front. `.canJoinAllSpaces` proved unreliable: after enough Space hopping the window ended up pinned
        // to a single Space and the switcher appeared on a desktop the user wasn't looking at.
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns one switching "session": from the moment the shortcut is pressed until the modifier is released.
@MainActor
final class SwitcherController {
    static let shared = SwitcherController()

    let model = SwitcherModel()
    private let panel = SwitcherPanel()
    private(set) var isActive = false
    private var panelVisible = false
    private var showTimer: Timer?
    private var watchdog: Timer?
    private var mouseAtShow = NSEvent.mouseLocation

    private let backdrop = NSVisualEffectView()

    private init() {
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.maskImage = Self.roundedMask(radius: Layout.corner)

        let host = ClickThroughHostingView(rootView: SwitcherView(
            model: model,
            actions: TileActions(
                hover: { [weak self] i in self?.hovered(i) },
                click: { [weak self] i in self?.clicked(i) },
                close: { [weak self] i in self?.closeWindow(at: i) },
                minimize: { [weak self] i in self?.toggleMinimize(at: i) },
                fullscreen: { [weak self] i in self?.toggleFullscreen(at: i) })))
        host.sizingOptions = []

        let container = NSView()
        for view in [backdrop, host] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        panel.contentView = container
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let img = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }

    // MARK: Session lifecycle

    @discardableResult
    func begin(mode: SwitchMode, reverse: Bool) -> Bool {
        guard !isActive else { return true }
        let list = WindowProvider.windows(mode: mode)
        guard !list.isEmpty else { return false }
        model.windows = list
        model.selected = list.count > 1 ? (reverse ? list.count - 1 : 1) : 0
        isActive = true
        debugLog("begin: \(list.count) windows")

        let delay = Settings.shared.showDelay
        if delay <= 0 {
            showPanel()
        } else {
            // .common modes so the delay still fires while a menu or other tracking loop is running.
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.showPanel() }
            }
            RunLoop.main.add(timer, forMode: .common)
            showTimer = timer
        }
        startWatchdog()
        return true
    }

    /// If the key-up for the trigger modifier is ever lost (event tap hiccup, secure input), don't leave the
    /// session stuck open swallowing keys: notice the modifier is no longer held and finish the switch.
    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                let held = CGEventSource.flagsState(.combinedSessionState)
                if !held.contains(Settings.shared.triggerModifier.flag) {
                    debugLog("watchdog: trigger modifier no longer held, committing")
                    self.commit()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    func commit() {
        guard isActive else { return }
        let target = model.windows.indices.contains(model.selected) ? model.windows[model.selected] : nil
        end()
        if let target { WindowActions.focus(target) }
    }

    func cancel() { end() }

    private func end() {
        showTimer?.invalidate()
        showTimer = nil
        watchdog?.invalidate()
        watchdog = nil
        panel.orderOut(nil)
        panelVisible = false
        isActive = false
        model.rows = []       // clear the layout together with the windows it indexes
        model.windows = []
    }

    // MARK: Navigation

    func advance(_ delta: Int) {
        guard isActive, !model.windows.isEmpty else { return }
        let n = model.windows.count
        model.selected = ((model.selected + delta) % n + n) % n
        showPanel()
    }

    func moveVertically(_ rows: Int) {
        guard isActive, !model.windows.isEmpty else { return }
        model.moveVertically(rows)
        showPanel()
    }

    private func hovered(_ index: Int) {
        guard isActive, index != model.selected else { return }
        // Ignore the "hover" caused by the panel simply appearing under a stationary pointer.
        let p = NSEvent.mouseLocation
        guard abs(p.x - mouseAtShow.x) > 2 || abs(p.y - mouseAtShow.y) > 2 else { return }
        model.selected = index
    }

    private func clicked(_ index: Int) {
        guard isActive, model.windows.indices.contains(index) else { return }
        model.selected = index
        commit()
    }

    // MARK: Window actions while the switcher is open

    func quitSelectedApp() {
        guard let w = selectedWindow else { return }
        WindowActions.quit(pid: w.pid)
        remove { $0.pid == w.pid }
    }

    func closeSelectedWindow() { closeWindow(at: model.selected) }
    func toggleMinimizeSelected() { toggleMinimize(at: model.selected) }
    func hideSelectedApp() {
        guard let w = selectedWindow else { return }
        WindowActions.hide(pid: w.pid)
        for other in model.windows where other.pid == w.pid { other.isAppHidden = true }
    }

    func closeWindow(at index: Int) {
        guard isActive, model.windows.indices.contains(index) else { return }
        let w = model.windows[index]
        WindowActions.close(w)
        remove { $0.id == w.id }
    }

    func toggleMinimize(at index: Int) {
        guard isActive, model.windows.indices.contains(index) else { return }
        WindowActions.toggleMinimize(model.windows[index])
    }

    func toggleFullscreen(at index: Int) {
        guard isActive, model.windows.indices.contains(index) else { return }
        WindowActions.toggleFullscreen(model.windows[index])
    }

    private var selectedWindow: WindowInfo? {
        isActive && model.windows.indices.contains(model.selected) ? model.windows[model.selected] : nil
    }

    private func remove(where predicate: (WindowInfo) -> Bool) {
        let selectedID = selectedWindow?.id
        model.windows.removeAll(where: predicate)
        if model.windows.isEmpty { cancel(); return }
        model.selected = model.windows.firstIndex { $0.id == selectedID } ?? min(model.selected, model.windows.count - 1)
        if panelVisible { layoutPanel() }
    }

    // MARK: Panel

    private func showPanel(loadThumbnails: Bool = true) {
        guard isActive else { return }
        // Already up? Only skip when the window server really has it on screen; otherwise bring it back.
        if panelVisible, panel.isVisible { return }
        panel.appearance = Settings.shared.theme.appearance
        backdrop.isHidden = Settings.shared.liquidGlass   // Liquid Glass draws its own backdrop
        mouseAtShow = NSEvent.mouseLocation
        layoutPanel()
        panel.orderFrontRegardless()
        panelVisible = true
        keepPanelOnCurrentSpace(allowUnplaced: false)
        debugLog("panel shown on \(targetScreen.localizedName)")
        verifyPanelOnScreen()
        guard loadThumbnails, !PerfFlags.noThumbCapture else { return }
        let backing = targetScreen.backingScaleFactor
        ThumbnailService.shared.apply(to: model.windows, pixelHeight: Settings.shared.tileSize.thumbHeight * model.scale * backing)
    }

    /// The screen the pointer is on: that is where the user is looking (NSScreen.main follows the key window,
    /// which for a background utility can be a different display).
    private var targetScreen: NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Shortly after showing, confirm the panel is really on screen; macOS occasionally drops an ordered-front
    /// window (Space changes, display wake). If it did, put it back. With debug logging on, also record where the
    /// panel is and save a snapshot of what it actually draws (~/Library/Logs/Whisk-panel.png).
    private func verifyPanelOnScreen(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.isActive else { return }
            if !self.panel.isVisible {
                debugLog("panel not visible after show (attempt \(attempt)), re-ordering front")
                self.layoutPanel()
                self.panel.orderFrontRegardless()
                if attempt < 3 { self.verifyPanelOnScreen(attempt: attempt + 1) }
                return
            }
            self.keepPanelOnCurrentSpace()
            self.logPanelState()
        }
    }

    /// The Space shown on the given display right now (not the "active" Space, which lags during a Space switch).
    private func currentSpace(on screen: NSScreen) -> Int {
        let cid = CGSMainConnectionID()
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
           let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
           let uuidString = CFUUIDCreateString(nil, uuid) as String?,
           let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] {
            for d in displays where (d["Display Identifier"] as? String) == uuidString {
                if let id = (d["Current Space"] as? [String: Any])?["id64"] as? Int { return id }
            }
        }
        return CGSGetActiveSpace(cid)
    }

    /// If the panel is not on the Space the user is looking at, move it there.
    private func keepPanelOnCurrentSpace(allowUnplaced: Bool = true) {
        let wid = panel.windowNumber
        guard wid > 0 else { return }
        let cid = CGSMainConnectionID()
        let target = currentSpace(on: targetScreen)
        let on = CGSCopySpacesForWindows(cid, 7, [wid] as CFArray) as? [Int] ?? []
        guard !on.contains(target) else { return }
        // Right after ordering front the window server may not have placed the window yet; the delayed check handles that.
        if on.isEmpty, !allowUnplaced { return }
        debugLog("panel was on spaces \(on) but current space is \(target): moving it")
        CGSMoveWindowsToManagedSpace(cid, [wid] as CFArray, target)
        panel.orderFrontRegardless()
    }

    private func logPanelState() {
        guard UserDefaults.standard.bool(forKey: "debugLog") else { return }
        let cid = CGSMainConnectionID()
        let wid = panel.windowNumber
        let spaces = CGSCopySpacesForWindows(cid, 7, [wid] as CFArray) as? [Int] ?? []
        debugLog("panel state: wid=\(wid) frame=\(panel.frame) visible=\(panel.isVisible) occlusion=\(panel.occlusionState.rawValue) screen=\(panel.screen?.localizedName ?? "none") windowSpaces=\(spaces) activeSpace=\(CGSGetActiveSpace(cid)) mouse=\(NSEvent.mouseLocation) appHidden=\(NSApp.isHidden) policy=\(NSApp.activationPolicy().rawValue)")
        if let cg = ThumbnailService.captureWindowList(CGWindowID(wid)) {
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Whisk-panel.png")
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
            debugLog("panel snapshot saved: \(cg.width)x\(cg.height)")
        } else {
            debugLog("panel snapshot failed")
        }
    }

    private func layoutPanel() {
        let screen = targetScreen
        let visible = screen.visibleFrame
        let size = model.layout(maxWidth: visible.width * 0.92, maxHeight: visible.height * 0.85)
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    // MARK: Developer aid

    /// Shows the panel with the given windows, without touching the real window list or capturing thumbnails.
    func showForDebug(windows: [WindowInfo]) -> NSWindow {
        model.windows = windows
        model.selected = 0
        isActive = true
        showPanel(loadThumbnails: false)
        return panel
    }

    func debugSelect(_ index: Int) { model.selected = index }
    var debugPanelView: NSView? { panel.contentView }
    var debugWindowNumbers: [Int] { [panel.windowNumber] }
    func debugEnd() { end() }
}
