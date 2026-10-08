import AppKit
import ApplicationServices

/// Tracks which windows you used most recently.
///
/// CoreGraphics' window list is a z-order, not a usage history: it only reflects stacking on the current Space,
/// so windows on other Spaces and in fullscreen apps land in arbitrary positions and the window you just left is
/// not reliably second in the switcher. This keeps a real most-recently-used list instead.
final class RecentWindows: @unchecked Sendable {
    static let shared = RecentWindows()

    private let lock = NSLock()
    private var order: [CGWindowID] = []
    private let queue = DispatchQueue(label: "whisk.recent-windows", qos: .utility)

    /// Starts watching which window has focus.
    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.queue.async { self?.sampleFocusedWindow() }
        }
        // Window changes inside one app (two Chrome windows, say) don't activate an app, so also sample regularly.
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.queue.async { self?.sampleFocusedWindow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        queue.async { [weak self] in self?.sampleFocusedWindow() }
    }

    /// Records a window as the most recently used.
    func note(_ wid: CGWindowID) {
        guard wid != 0 else { return }
        lock.lock(); defer { lock.unlock() }
        if order.first == wid { return }
        order.removeAll { $0 == wid }
        order.insert(wid, at: 0)
        if order.count > 400 { order.removeLast(order.count - 400) }
    }

    /// Reads the focused window of the frontmost app right now (call before building the list so #1 is current).
    func sampleFocusedWindow() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.15)
        guard let win = AX.attr(ax, kAXFocusedWindowAttribute) as AXUIElement? else { return }
        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(win, &wid) == .success else { return }
        note(wid)
    }

    /// Position of each known window in the usage history (0 = most recent).
    func ranks() -> [CGWindowID: Int] {
        lock.lock(); defer { lock.unlock() }
        var r = [CGWindowID: Int](minimumCapacity: order.count)
        for (i, wid) in order.enumerated() { r[wid] = i }
        return r
    }
}
