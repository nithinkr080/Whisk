import ScreenCaptureKit
import SwiftUI

/// Sample windows with generated thumbnails, used by the Appearance preview and the `--preview` developer aid.
@MainActor
func makeSampleWindows(count: Int) -> [WindowInfo] {
    let apps = ["/System/Applications/Utilities/Terminal.app", "/System/Applications/Mail.app", "/System/Applications/Notes.app",
                "/System/Applications/Calendar.app", "/System/Applications/Maps.app", "/System/Applications/Music.app",
                "/System/Applications/Utilities/Activity Monitor.app", "/System/Applications/Messages.app"]
    let titles = ["Terminal", "Mail", "Notes", "Calendar", "Maps", "Music", "Activity Monitor", "Messages"]
    let sizes: [CGSize] = [CGSize(width: 800, height: 500), CGSize(width: 1200, height: 800), CGSize(width: 700, height: 700),
                           CGSize(width: 1512, height: 949), CGSize(width: 1000, height: 650), CGSize(width: 1512, height: 949)]
    let hues: [CGFloat] = [0.58, 0.08, 0.14, 0.0, 0.38, 0.85, 0.5, 0.65]

    func fakeThumb(_ size: CGSize, hue: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size.width / 3, height: size.height / 3), flipped: false) { r in
            NSGradient(colors: [NSColor(hue: hue, saturation: 0.45, brightness: 0.95, alpha: 1),
                                NSColor(hue: hue, saturation: 0.7, brightness: 0.55, alpha: 1)])!.draw(in: r, angle: -70)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: r.maxY - 14, width: r.width, height: 14)).fill()
            NSColor.white.withAlphaComponent(0.35).setFill()
            for i in 0..<5 { NSBezierPath(roundedRect: NSRect(x: 14, y: r.maxY - 40 - CGFloat(i) * 22, width: r.width * (0.3 + 0.1 * CGFloat(i % 3)), height: 12), xRadius: 4, yRadius: 4).fill() }
            return true
        }
    }

    return (0..<count).map { i in
        let size = sizes[i % sizes.count]
        let w = WindowInfo(id: CGWindowID(i + 1), pid: 1, appName: "App", bundleID: nil,
                           icon: NSWorkspace.shared.icon(forFile: apps[i % apps.count]),
                           bounds: CGRect(origin: .zero, size: size), axWindow: nil, onOtherSpace: false,
                           title: titles[i % titles.count], isMinimized: false, isAppHidden: false, isFullscreen: false)
        w.thumbnail = fakeThumb(size, hue: hues[i % hues.count])
        return w
    }
}

/// Developer aid: `Whisk --preview out.png [dark|light] [count]` renders the switcher with sample windows.
@MainActor
func renderSwitcherPreview(path: String, dark: Bool, count: Int) {
    let model = SwitcherModel()
    model.windows = makeSampleWindows(count: count)
    model.selected = min(1, count - 1)
    let size = model.layout(maxWidth: 1300, maxHeight: 800)

    let panel = SwitcherView(model: model, actions: TileActions(hover: { _ in }, click: { _ in }, close: { _ in }, minimize: { _ in }, fullscreen: { _ in }))
        .frame(width: size.width, height: size.height)
        .background(RoundedRectangle(cornerRadius: Layout.corner, style: .continuous).fill(Color(white: dark ? 0.17 : 0.93)))
        .environment(\.colorScheme, dark ? .dark : .light)
    let stage = panel.padding(40).background(LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
    let renderer = ImageRenderer(content: stage)
    renderer.scale = 2
    if let cg = renderer.cgImage {
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

/// Developer aid: `Whisk --list` prints what the switcher would show; `--focus <windowID>` runs the real focus path.
@MainActor
func debugListWindows(focus wid: Int?) {
    let cid = CGSMainConnectionID()
    print("active space:", CGSGetActiveSpace(cid))
    let list = WindowProvider.windows(mode: .allApps)
    for (i, w) in list.enumerated() {
        print(i, w.id, w.appName, "| title:", w.title, "| otherSpace:", w.onOtherSpace, "| fullscreen:", w.isFullscreen,
              "| ax:", w.axWindow != nil, "| \(Int(w.bounds.width))x\(Int(w.bounds.height))")
    }
    if let wid, let w = list.first(where: { Int($0.id) == wid }) {
        func onScreen() -> String {
            ((CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? [])
                .filter { ($0[kCGWindowLayer as String] as? Int) == 0 && ((($0[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double) ?? 0) > 300 }
                .map { "\($0[kCGWindowOwnerName as String] ?? "?")#\($0[kCGWindowNumber as String] ?? 0)" }.prefix(6).joined(separator: ", ")
        }
        let startSpace = CGSGetActiveSpace(cid)
        let home = list.first { !$0.onOtherSpace && !$0.isMinimized }
        WindowActions.focus(w)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        print("after focus: active space", CGSGetActiveSpace(cid), "| frontmost:", NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")
        print("   really on screen:", onScreen())
        if let home, home.id != w.id { WindowActions.focus(home) }
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        print("restored: active space", CGSGetActiveSpace(cid), "(started in \(startSpace)) | on screen:", onScreen())
    } else if let wid { print("window \(wid) is NOT in the switcher list") }
}

/// Developer aid: `Whisk --capture <windowID> <out-prefix>` tries each capture API on one window.
func debugCapture(windowID: CGWindowID, prefix: String) {
    func save(_ cg: CGImage, _ name: String) {
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
    }
    var report = [String]()
    // 1. ScreenCaptureKit
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
           let sc = content.windows.first(where: { $0.windowID == windowID }) {
            report.append("SCK: window listed, onScreen=\(sc.isOnScreen) frame=\(sc.frame)")
            let cfg = SCStreamConfiguration(); cfg.width = Int(sc.frame.width / 2); cfg.height = Int(sc.frame.height / 2)
            if let img = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: sc), configuration: cfg) {
                report.append("SCK: captured \(img.width)x\(img.height)"); save(img, "sck")
            } else { report.append("SCK: capture FAILED") }
        } else { report.append("SCK: window not listed") }
        sem.signal()
    }
    while sem.wait(timeout: .now()) == .timedOut { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    // 2. CGWindowListCreateImage (looked up at runtime; deprecated)
    typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
        let fn = unsafeBitCast(sym, to: Fn.self)
        if let img = fn(.null, 1 << 3, windowID, (1 << 0) | (1 << 4))?.takeRetainedValue() {
            report.append("CGWindowListCreateImage: captured \(img.width)x\(img.height)"); save(img, "cg")
        } else { report.append("CGWindowListCreateImage: returned nil") }
    } else { report.append("CGWindowListCreateImage: symbol missing") }
    try? report.joined(separator: "\n").write(toFile: "\(prefix)-report.txt", atomically: true, encoding: .utf8)
}

/// Developer aid: `Whisk --thumbs <report.txt>` runs the thumbnail service over the real window list.
@MainActor
func debugThumbnails(report path: String) {
    let list = WindowProvider.windows(mode: .allApps)
    ThumbnailService.shared.apply(to: list, pixelHeight: 280)
    RunLoop.current.run(until: Date().addingTimeInterval(6))
    let lines = list.map { "\($0.thumbnail != nil ? "OK  " : "MISS") \($0.id) \($0.appName) otherSpace=\($0.onOtherSpace) fullscreen=\($0.isFullscreen) min=\($0.isMinimized)" }
    let got = list.filter { $0.thumbnail != nil }.count
    try? (["\(got)/\(list.count) windows have a preview"] + lines).joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
}

/// Developer aid: `Whisk --prefs-shot <prefix>` writes a PNG of each Preferences page.
@MainActor
func debugPreferencesScreenshots(prefix: String) {
    let window = makePreferencesWindow()
    window.orderFrontRegardless()
    for tab in PrefsTab.allCases {
        PrefsNavigation.shared.tab = tab
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        if let cg = ThumbnailService.captureWindowList(CGWindowID(window.windowNumber)) {
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(prefix)-\(tab.rawValue).png"))
        }
    }
}

/// Developer aid: `Whisk --liquid-shot <prefix> [classic]` shows the panel over a gradient backdrop window and
/// saves frames while the selection moves, compositing only those two windows (nothing from the user's screen).
@MainActor
func debugLiquidFrames(prefix: String, liquid: Bool, frost: Double? = nil) {
    Settings.shared.liquidGlass = liquid
    if let frost { Settings.shared.glassFrost = frost }
    let controller = SwitcherController.shared
    let panel = controller.showForDebug(windows: makeSampleWindows(count: 5))
    let area = panel.frame.insetBy(dx: -90, dy: -90)

    let backdrop = NSWindow(contentRect: area, styleMask: .borderless, backing: .buffered, defer: false)
    backdrop.level = .floating
    backdrop.isOpaque = true
    backdrop.contentView = NSHostingView(rootView: ZStack {
        LinearGradient(colors: [Color(red: 0.12, green: 0.30, blue: 0.75), Color(red: 0.55, green: 0.25, blue: 0.70), Color(red: 0.95, green: 0.50, blue: 0.35)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        HStack(spacing: 40) { ForEach(0..<6, id: \.self) { _ in Circle().fill(Color.white.opacity(0.25)).frame(width: 90) } }
    })
    backdrop.orderFront(nil)
    panel.orderFrontRegardless()
    func wait(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
    wait(0.8)

    typealias FromArray = @convention(c) (CGRect, CFArray, UInt32) -> Unmanaged<CGImage>?
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImageFromArray") else {
        debugLog("liquid-shot: CGWindowListCreateImageFromArray symbol missing"); return
    }
    let capture = unsafeBitCast(sym, to: FromArray.self)
    // CGWindowListCreateImageFromArray wants raw CGWindowID values stored as pointers, not boxed numbers.
    var rawIDs: [UnsafeRawPointer?] = controller.debugWindowNumbers.map { UnsafeRawPointer(bitPattern: UInt($0)) } + [UnsafeRawPointer(bitPattern: UInt(backdrop.windowNumber))]
    let ids = CFArrayCreate(nil, &rawIDs, rawIDs.count, nil)!
    let screenH = NSScreen.screens.first?.frame.height ?? 0
    let rect = CGRect(x: area.minX, y: screenH - area.maxY, width: area.width, height: area.height)
    func shot(_ name: String) {
        let cg = capture(rect, ids, 1 << 0)?.takeRetainedValue()
        debugLog("liquid-shot \(name): \(cg == nil ? "nil" : "\(cg!.width)x\(cg!.height)") rect=\(rect) panel=\(panel.windowNumber) backdrop=\(backdrop.windowNumber)")
        if let cg {
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
        }
    }
    shot("0-start")
    controller.debugSelect(3)
    for (i, t) in [0.07, 0.07, 0.1, 0.9].enumerated() { wait(t); shot("\(i + 1)-moving") }
    controller.debugEnd()
    backdrop.orderOut(nil)
}

/// Counts display-link callbacks; a long gap between two means the main thread (or the display) stalled.
final class FrameTicker: NSObject {
    var stamps = [CFTimeInterval]()
    @objc func tick(_ link: CADisplayLink) { stamps.append(link.timestamp) }
}

/// Developer aid: `Whisk --liquid-perf <report> [flags...]` plays the Liquid Glass selection animation and
/// reports frame pacing. Flags: n=<tile count>, classic.
@MainActor
func debugLiquidPerf(report path: String, flags: [String]) {
    Settings.shared.liquidGlass = !flags.contains("classic")
    let count = flags.compactMap { $0.hasPrefix("n=") ? Int($0.dropFirst(2)) : nil }.first ?? 8
    let panel = SwitcherController.shared.showForDebug(windows: makeSampleWindows(count: count))
    panel.orderFrontRegardless()
    func wait(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
    wait(1.0)

    let ticker = FrameTicker()
    guard let view = panel.contentView else { return }
    let link = view.displayLink(target: ticker, selector: #selector(FrameTicker.tick(_:)))
    link.add(to: .main, forMode: .common)
    wait(0.3)
    ticker.stamps.removeAll()
    let start = CACurrentMediaTime()
    for i in 1...12 {
        SwitcherController.shared.debugSelect(i % count)
        wait(0.45)
    }
    let elapsed = CACurrentMediaTime() - start
    link.invalidate()
    SwitcherController.shared.debugEnd()
    wait(0.6)   // let SwiftUI redraw after the panel closes, as in real use

    let gaps = zip(ticker.stamps.dropFirst(), ticker.stamps).map { $0 - $1 }.sorted()
    let nominal = gaps.isEmpty ? 0 : gaps[gaps.count / 2]
    let dropped = gaps.filter { $0 > nominal * 1.5 }.count
    let p95 = gaps.isEmpty ? 0 : gaps[Int(Double(gaps.count - 1) * 0.95)]
    let line = String(format: "flags=%@ | frames=%d over %.1fs (%.0f fps) | median gap %.1f ms | p95 %.1f ms | worst %.1f ms | slow frames %d (%.1f%%)",
                      flags.isEmpty ? "none" : flags.joined(separator: ","), ticker.stamps.count, elapsed,
                      Double(ticker.stamps.count) / elapsed, nominal * 1000, p95 * 1000, (gaps.last ?? 0) * 1000,
                      dropped, gaps.isEmpty ? 0 : Double(dropped) / Double(gaps.count) * 100)
    if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); try? h.close() }
    else { try? (line + "\n").write(toFile: path, atomically: true, encoding: .utf8) }
}

/// Developer aid: `Whisk --real-perf <report> [noThumbCapture]` opens the switcher on the REAL windows (as ⌥Tab
/// does), steps the selection like a user tapping Tab, and reports where frames were lost.
@MainActor
func debugRealPerf(report path: String, flags: [String]) {
    PerfFlags.noThumbCapture = flags.contains("noThumbCapture")
    let settings = Settings.shared
    let savedDelay = settings.showDelay, savedLiquid = settings.liquidGlass
    settings.showDelay = 0
    settings.liquidGlass = !flags.contains("classic")
    defer { settings.showDelay = savedDelay; settings.liquidGlass = savedLiquid }

    let controller = SwitcherController.shared
    let ticker = FrameTicker()
    let t0 = CACurrentMediaTime()
    let began = controller.begin(mode: .allApps, reverse: false)
    let beginMs = (CACurrentMediaTime() - t0) * 1000
    guard began, let view = controller.debugPanelView else { return }
    let link = view.displayLink(target: ticker, selector: #selector(FrameTicker.tick(_:)))
    link.add(to: .main, forMode: .common)
    let start = CACurrentMediaTime()
    for _ in 0..<12 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        controller.advance(1)
    }
    link.invalidate()
    controller.cancel()
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))

    var slow = [String]()
    for (a, b) in zip(ticker.stamps, ticker.stamps.dropFirst()) where b - a > 0.0125 {
        slow.append(String(format: "+%.2fs:%.0fms", a - start, (b - a) * 1000))
    }
    let line = "flags=\(flags.isEmpty ? "none" : flags.joined(separator: ",")) | open (list windows + show panel) took \(Int(beginMs)) ms | slow frames (>12.5ms): \(slow.count) of \(ticker.stamps.count) | \(slow.prefix(14).joined(separator: " "))"
    if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); try? h.close() }
    else { try? (line + "\n").write(toFile: path, atomically: true, encoding: .utf8) }
}
