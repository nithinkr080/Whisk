import AppKit
import ApplicationServices

enum SwitchMode { case allApps, currentApp }

final class WindowInfo: ObservableObject, Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let bundleID: String?
    let icon: NSImage
    let bounds: CGRect
    var axWindow: AXUIElement?
    var onOtherSpace: Bool
    var spaceKey = 0
    var displayUUID: String?
    @Published var title: String
    @Published var isMinimized: Bool
    @Published var isAppHidden: Bool
    @Published var isFullscreen: Bool
    @Published var thumbnail: NSImage?

    init(id: CGWindowID, pid: pid_t, appName: String, bundleID: String?, icon: NSImage, bounds: CGRect,
         axWindow: AXUIElement?, onOtherSpace: Bool, title: String, isMinimized: Bool, isAppHidden: Bool, isFullscreen: Bool) {
        self.id = id; self.pid = pid; self.appName = appName; self.bundleID = bundleID; self.icon = icon
        self.bounds = bounds; self.axWindow = axWindow; self.onOtherSpace = onOtherSpace; self.title = title
        self.isMinimized = isMinimized; self.isAppHidden = isAppHidden; self.isFullscreen = isFullscreen
    }
}

enum AX {
    static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success, let v else { return nil }
        return v as? T
    }
}

enum WindowProvider {
    private struct AXWin {
        let element: AXUIElement
        let title: String
        let minimized: Bool
        let fullscreen: Bool
    }

    /// Windows ordered front-to-back (most recently used first).
    static func windows(mode: SwitchMode) -> [WindowInfo] {
        let s = Settings.shared
        let me = ProcessInfo.processInfo.processIdentifier
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        var apps = [pid_t: NSRunningApplication]()
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isTerminated && app.processIdentifier != me {
            if let b = app.bundleIdentifier, s.excludedBundleIDs.contains(b) { continue }
            if mode == .currentApp, app.processIdentifier != frontPID { continue }
            apps[app.processIdentifier] = app
        }

        // Query every app's windows in parallel so one slow app can't hold up (or drop out of) the list.
        var ax = [CGWindowID: (pid: pid_t, win: AXWin)]()
        let pids = Array(apps.keys)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: pids.count) { i in
            let found = axWindows(for: pids[i])
            lock.lock()
            for (wid, w) in found { ax[wid] = (pids[i], w) }
            lock.unlock()
        }

        let mouseScreenFrame: CGRect? = {
            guard s.screenFilter == .mouseScreen else { return nil }
            let p = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }?.frame
        }()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let primaryWidth = NSScreen.screens.first?.frame.width ?? 0
        let snapshot = SpaceSnapshot()

        var result = [WindowInfo]()
        var seen = Set<CGWindowID>()

        func add(_ info: WindowInfo) {
            guard seen.insert(info.id).inserted else { return }
            if !s.showMinimized && info.isMinimized { return }
            if !s.showHiddenApps && info.isAppHidden { return }
            if !s.showFullscreen && info.isFullscreen { return }
            if !s.showOtherSpaces && info.onOtherSpace { return }
            if let frame = mouseScreenFrame {
                let center = CGPoint(x: info.bounds.midX, y: primaryHeight - info.bounds.midY)
                if !frame.contains(center) { return }
            }
            result.append(info)
        }

        let cgList = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
        for d in cgList {
            guard (d[kCGWindowLayer as String] as? Int) == 0,
                  let widNum = d[kCGWindowNumber as String] as? Int,
                  let pidNum = d[kCGWindowOwnerPID as String] as? Int,
                  let app = apps[pid_t(pidNum)] else { continue }
            let wid = CGWindowID(widNum)
            let alpha = (d[kCGWindowAlpha as String] as? Double) ?? 1
            guard alpha > 0.01 else { continue }
            var bounds = CGRect.zero
            if let bd = d[kCGWindowBounds as String] { bounds = CGRect(dictionaryRepresentation: bd as! CFDictionary) ?? .zero }
            guard bounds.width >= 80, bounds.height >= 50 else { continue }
            let cgTitle = (d[kCGWindowName as String] as? String) ?? ""
            let onScreen = (d[kCGWindowIsOnscreen as String] as? Bool) ?? false

            if let entry = ax[wid] {
                let info = makeInfo(wid: wid, app: app, bounds: bounds, ax: entry.win, title: entry.win.title.isEmpty ? cgTitle : entry.win.title, otherSpace: false)
                applySpace(to: info, snapshot: snapshot)
                add(info)
            } else if isPlausibleWindow(bounds, primaryWidth: primaryWidth) {
                // Not reported by Accessibility. macOS's own Space data decides what this window is
                // (the "on screen" flag is unreliable for windows in other Spaces).
                let spaces = snapshot.spaces(of: wid)
                guard !spaces.isEmpty else { continue }   // helper / offscreen surface owned by no Space
                if snapshot.visible.isDisjoint(with: spaces) {
                    // Lives in another Space (including a fullscreen app's own Space).
                    let info = makeInfo(wid: wid, app: app, bounds: bounds, ax: nil, title: cgTitle, otherSpace: false)
                    applySpace(to: info, snapshot: snapshot)
                    add(info)
                } else if onScreen {
                    // Visible right now but Accessibility missed it (e.g. the app answered too slowly).
                    add(makeInfo(wid: wid, app: app, bounds: bounds, ax: nil, title: cgTitle, otherSpace: false))
                }
            }
        }

        // Anything Accessibility knows about that CoreGraphics did not list.
        for (wid, entry) in ax.sorted(by: { $0.key < $1.key }) where !seen.contains(wid) {
            guard let app = apps[entry.pid] else { continue }
            let frame = (AX.attr(entry.win.element, kAXPositionAttribute) as AXValue?).flatMap { pos -> CGRect? in
                var p = CGPoint.zero; var sz = CGSize.zero
                AXValueGetValue(pos, .cgPoint, &p)
                if let sv = AX.attr(entry.win.element, kAXSizeAttribute) as AXValue? { AXValueGetValue(sv, .cgSize, &sz) }
                return CGRect(origin: p, size: sz)
            } ?? .zero
            let info = makeInfo(wid: wid, app: app, bounds: frame, ax: entry.win, title: entry.win.title, otherSpace: false)
            applySpace(to: info, snapshot: snapshot)
            add(info)
        }

        // A fullscreen app's own Space often holds small overlay surfaces (popups, toolbars) next to the real
        // window. Only there, keep just the windows comparable in size to the largest one. Regular desktops are untouched.
        var largest = [String: CGFloat]()
        func key(_ w: WindowInfo) -> String { "\(w.pid)-\(w.spaceKey)" }
        func isFullscreenSpaceWindow(_ w: WindowInfo) -> Bool { w.onOtherSpace && w.isFullscreen }
        for w in result where isFullscreenSpaceWindow(w) { largest[key(w), default: 0] = max(largest[key(w)] ?? 0, w.bounds.width * w.bounds.height) }
        result.removeAll { isFullscreenSpaceWindow($0) && $0.bounds.width * $0.bounds.height < (largest[key($0)] ?? 0) * 0.3 }
        return result
    }

    /// Marks a window as living in another Space based on macOS's Space data. Accessibility alone can't tell:
    /// some apps (e.g. VS Code) report windows of every Space, which would skip the Space switch on focus.
    private static func applySpace(to info: WindowInfo, snapshot: SpaceSnapshot) {
        let spaces = snapshot.spaces(of: info.id)
        guard !spaces.isEmpty, snapshot.visible.isDisjoint(with: spaces) else { return }
        let space = spaces.first { snapshot.isFullscreenSpace($0) } ?? spaces[0]
        info.onOtherSpace = true
        info.spaceKey = space
        info.displayUUID = snapshot.display(of: space)
        if snapshot.isFullscreenSpace(space) { info.isFullscreen = true }
    }

    /// Filters out menu-bar strips, fullscreen toolbar overlays and other non-window surfaces.
    private static func isPlausibleWindow(_ b: CGRect, primaryWidth: CGFloat) -> Bool {
        guard b.width >= 80, b.height >= 60 else { return false }
        if b.height < 200, b.width > primaryWidth * 0.8 { return false }
        return true
    }

    private static func makeInfo(wid: CGWindowID, app: NSRunningApplication, bounds: CGRect, ax: AXWin?, title: String, otherSpace: Bool) -> WindowInfo {
        let name = app.localizedName ?? "App"
        let icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        return WindowInfo(id: wid, pid: app.processIdentifier, appName: name, bundleID: app.bundleIdentifier, icon: icon,
                          bounds: bounds, axWindow: ax?.element, onOtherSpace: otherSpace,
                          title: title.isEmpty ? name : title,
                          isMinimized: ax?.minimized ?? false, isAppHidden: app.isHidden, isFullscreen: ax?.fullscreen ?? false)
    }

    private static func axWindows(for pid: pid_t) -> [CGWindowID: AXWin] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        guard let wins: [AXUIElement] = AX.attr(app, kAXWindowsAttribute) else { return [:] }
        var out = [CGWindowID: AXWin]()
        for w in wins {
            var wid: CGWindowID = 0
            guard _AXUIElementGetWindow(w, &wid) == .success, wid != 0 else { continue }
            let role: String? = AX.attr(w, kAXRoleAttribute)
            guard role == kAXWindowRole else { continue }
            let sub: String? = AX.attr(w, kAXSubroleAttribute)
            let title: String = AX.attr(w, kAXTitleAttribute) ?? ""
            let ok = sub == kAXStandardWindowSubrole || sub == kAXDialogSubrole || sub == kAXSystemDialogSubrole
                || (sub == nil && !title.isEmpty)
            guard ok else { continue }
            let minimized: Bool = AX.attr(w, kAXMinimizedAttribute) ?? false
            let fullscreen: Bool = AX.attr(w, "AXFullScreen") ?? false
            out[wid] = AXWin(element: w, title: title, minimized: minimized, fullscreen: fullscreen)
        }
        return out
    }
}

enum WindowActions {
    static func focus(_ w: WindowInfo) {
        debugLog("focus wid=\(w.id) app=\(w.appName) otherSpace=\(w.onOtherSpace) space=\(w.spaceKey) ax=\(w.axWindow != nil) min=\(w.isMinimized)")
        // Raising the window's own Accessibility element makes macOS switch to its Space natively (with the
        // normal animation), including fullscreen Spaces. Other-Space windows have no element yet: find it.
        if w.onOtherSpace, w.axWindow == nil {
            w.axWindow = findAXWindow(pid: w.pid, windowID: w.id)
            debugLog("  probed accessibility element: \(w.axWindow != nil ? "found" : "NOT found")")
        }
        focusNow(w)
    }

    /// Probes the app's accessibility element ids until one is the window with the given id.
    private static func findAXWindow(pid: pid_t, windowID: CGWindowID, limit: UInt64 = 2500) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.08)
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: Int32(pid), toByteOffset: 0, as: Int32.self)
            raw.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
            raw.storeBytes(of: Int32(0x636f636f), toByteOffset: 8, as: Int32.self)   // "coco"
        }
        for id in 0..<limit {
            token.withUnsafeMutableBytes { $0.storeBytes(of: id, toByteOffset: 12, as: UInt64.self) }
            guard let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else { continue }
            var found: CGWindowID = 0
            if _AXUIElementGetWindow(element, &found) == .success, found == windowID,
               (AX.attr(element, kAXRoleAttribute) as String?) == kAXWindowRole {
                return element
            }
        }
        return nil
    }

    private static func focusNow(_ w: WindowInfo) {
        guard let app = NSRunningApplication(processIdentifier: w.pid) else { return }
        if app.isHidden { app.unhide() }
        if let ax = w.axWindow, w.isMinimized {
            AXUIElementSetAttributeValue(ax, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        var psn = ProcessSerialNumber()
        if skyLightFocusAvailable, GetProcessForPID(w.pid, &psn) == noErr {
            _ = _SLPSSetFrontProcessWithOptions(&psn, w.id, 0x200)
            makeKeyWindow(&psn, w.id)
        }
        if let ax = w.axWindow {
            AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
        } else {
            // No handle on the window at all: activating the app at least takes us to its last-used Space.
            app.activate()
        }
    }

    static func bringToFront(pid: pid_t, wid: CGWindowID) {
        var psn = ProcessSerialNumber()
        guard skyLightFocusAvailable, GetProcessForPID(pid, &psn) == noErr else { return }
        _ = _SLPSSetFrontProcessWithOptions(&psn, wid, 0x200)
        makeKeyWindow(&psn, wid)
    }

    private static func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID) {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        var w = wid
        memcpy(&bytes[0x3c], &w, MemoryLayout<UInt32>.size)
        memset(&bytes[0x20], 0xff, 0x10)
        bytes[0x08] = 0x01
        _ = SLPSPostEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = SLPSPostEventRecordTo(&psn, &bytes)
    }

    static func close(_ w: WindowInfo) {
        guard let ax = w.axWindow else { return }
        if let button: AXUIElement = AX.attr(ax, kAXCloseButtonAttribute) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    static func toggleMinimize(_ w: WindowInfo) {
        guard let ax = w.axWindow else { return }
        let target = !w.isMinimized
        if AXUIElementSetAttributeValue(ax, kAXMinimizedAttribute as CFString, target as CFBoolean) == .success {
            w.isMinimized = target
        }
    }

    static func toggleFullscreen(_ w: WindowInfo) {
        guard let ax = w.axWindow else { return }
        let target = !w.isFullscreen
        if AXUIElementSetAttributeValue(ax, "AXFullScreen" as CFString, target as CFBoolean) == .success {
            w.isFullscreen = target
        }
    }

    static func quit(pid: pid_t) { NSRunningApplication(processIdentifier: pid)?.terminate() }

    static func hide(pid: pid_t) { NSRunningApplication(processIdentifier: pid)?.hide() }
}
