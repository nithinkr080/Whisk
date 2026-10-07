import AppKit

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--preview"), args.count > i + 1 {
        _ = NSApplication.shared
        renderSwitcherPreview(path: args[i + 1], dark: !args.contains("light"),
                              count: args.compactMap(Int.init).first ?? 6)
        exit(0)
    }
    if let i = args.firstIndex(of: "--capture"), args.count > i + 2, let wid = UInt32(args[i + 1]) {
        _ = NSApplication.shared
        debugCapture(windowID: wid, prefix: args[i + 2])
        exit(0)
    }
    if let i = args.firstIndex(of: "--thumbs"), args.count > i + 1 {
        _ = NSApplication.shared
        debugThumbnails(report: args[i + 1])
        exit(0)
    }
    if let i = args.firstIndex(of: "--prefs-shot"), args.count > i + 1 {
        _ = NSApplication.shared
        debugPreferencesScreenshots(prefix: args[i + 1])
        exit(0)
    }
    if let i = args.firstIndex(of: "--liquid-shot"), args.count > i + 1 {
        _ = NSApplication.shared
        debugLiquidFrames(prefix: args[i + 1], liquid: !args.contains("classic"),
                          frost: args.firstIndex(of: "--frost").flatMap { args.count > $0 + 1 ? Double(args[$0 + 1]) : nil })
        exit(0)
    }
    if let i = args.firstIndex(of: "--liquid-perf"), args.count > i + 1 {
        _ = NSApplication.shared
        debugLiquidPerf(report: args[i + 1], flags: Array(args.dropFirst(i + 2)))
        exit(0)
    }
    if let i = args.firstIndex(of: "--real-perf"), args.count > i + 1 {
        _ = NSApplication.shared
        debugRealPerf(report: args[i + 1], flags: Array(args.dropFirst(i + 2)))
        exit(0)
    }
    if args.contains("--list") || args.contains("--focus") {
        _ = NSApplication.shared
        debugListWindows(focus: args.firstIndex(of: "--focus").flatMap { args.count > $0 + 1 ? Int(args[$0 + 1]) : nil })
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // menu-bar app, no Dock icon
    app.run()
}
