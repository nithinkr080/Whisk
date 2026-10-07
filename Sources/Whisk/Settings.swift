import SwiftUI
import ServiceManagement

enum TriggerModifier: String, CaseIterable, Identifiable {
    case option, control, command

    var id: String { rawValue }

    var title: String {
        switch self {
        case .option: return "Option (⌥)"
        case .control: return "Control (⌃)"
        case .command: return "Command (⌘) — replaces the system app switcher"
        }
    }

    var symbol: String {
        switch self {
        case .option: return "⌥"
        case .control: return "⌃"
        case .command: return "⌘"
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .command: return .maskCommand
        }
    }
}

enum TileSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var thumbHeight: CGFloat {
        switch self {
        case .small: return 100
        case .medium: return 140
        case .large: return 190
        }
    }
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum ScreenFilter: String, CaseIterable, Identifiable {
    case all, mouseScreen
    var id: String { rawValue }
    var title: String { self == .all ? "All screens" : "Only the screen with the mouse pointer" }
}

/// All user preferences, persisted in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var triggerModifier: TriggerModifier { didSet { d.set(triggerModifier.rawValue, forKey: "triggerModifier") } }
    @Published var tileSize: TileSize { didSet { d.set(tileSize.rawValue, forKey: "tileSize") } }
    @Published var theme: ThemeChoice { didSet { d.set(theme.rawValue, forKey: "theme") } }
    @Published var screenFilter: ScreenFilter { didSet { d.set(screenFilter.rawValue, forKey: "screenFilter") } }
    @Published var showThumbnails: Bool { didSet { d.set(showThumbnails, forKey: "showThumbnails") } }
    @Published var showTitles: Bool { didSet { d.set(showTitles, forKey: "showTitles") } }
    /// Experimental: Liquid Glass panel with a fluid selection that flows from window to window.
    @Published var liquidGlass: Bool { didSet { d.set(liquidGlass, forKey: "liquidGlass") } }
    /// Liquid Glass frostedness: 0 = crystal clear, 1 = heavily frosted.
    @Published var glassFrost: Double { didSet { d.set(glassFrost, forKey: "glassFrost") } }
    @Published var showMinimized: Bool { didSet { d.set(showMinimized, forKey: "showMinimized") } }
    @Published var showHiddenApps: Bool { didSet { d.set(showHiddenApps, forKey: "showHiddenApps") } }
    @Published var showFullscreen: Bool { didSet { d.set(showFullscreen, forKey: "showFullscreen") } }
    @Published var showOtherSpaces: Bool { didSet { d.set(showOtherSpaces, forKey: "showOtherSpaces") } }
    @Published var showMenuBarIcon: Bool { didSet { d.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    /// Seconds to wait before the panel appears. A quick tap switches without showing it.
    @Published var showDelay: Double { didSet { d.set(showDelay, forKey: "showDelay") } }
    @Published var excludedBundleIDs: [String] { didSet { d.set(excludedBundleIDs, forKey: "excludedBundleIDs") } }

    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Whisk: launch-at-login change failed: \(error)")
            }
        }
    }

    private init() {
        d.register(defaults: [
            "showThumbnails": true, "showTitles": true, "showMinimized": true, "showHiddenApps": true,
            "showFullscreen": true, "showOtherSpaces": true, "showMenuBarIcon": true, "showDelay": 0.1, "glassFrost": 0.3,
        ])
        triggerModifier = TriggerModifier(rawValue: d.string(forKey: "triggerModifier") ?? "") ?? .option
        tileSize = TileSize(rawValue: d.string(forKey: "tileSize") ?? "") ?? .medium
        theme = ThemeChoice(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        screenFilter = ScreenFilter(rawValue: d.string(forKey: "screenFilter") ?? "") ?? .all
        showThumbnails = d.bool(forKey: "showThumbnails")
        showTitles = d.bool(forKey: "showTitles")
        liquidGlass = d.bool(forKey: "liquidGlass")
        glassFrost = d.double(forKey: "glassFrost")
        showMinimized = d.bool(forKey: "showMinimized")
        showHiddenApps = d.bool(forKey: "showHiddenApps")
        showFullscreen = d.bool(forKey: "showFullscreen")
        showOtherSpaces = d.bool(forKey: "showOtherSpaces")
        showMenuBarIcon = d.bool(forKey: "showMenuBarIcon")
        showDelay = d.double(forKey: "showDelay")
        excludedBundleIDs = d.stringArray(forKey: "excludedBundleIDs") ?? []
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

}

enum Layout {
    static let pad: CGFloat = 22
    static let gap: CGFloat = 8
    static let tilePad: CGFloat = 10
    static let corner: CGFloat = 28
}
