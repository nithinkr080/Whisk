import SwiftUI
import UniformTypeIdentifiers

// MARK: - Navigation

enum PrefsTab: String, CaseIterable, Identifiable {
    case general, appearance, windows, permissions, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .windows: return "Windows"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Shortcuts and how Whisk behaves."
        case .appearance: return "Make the switcher look the way you like."
        case .windows: return "Choose which windows show up."
        case .permissions: return "What macOS lets Whisk do."
        case .about: return ""
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .windows: return "macwindow.on.rectangle"
        case .permissions: return "lock.shield.fill"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .purple
        case .windows: return .blue
        case .permissions: return .green
        case .about: return .orange
        }
    }
}

final class PrefsNavigation: ObservableObject {
    static let shared = PrefsNavigation()
    @Published var tab: PrefsTab = .general
}

@MainActor
func makePreferencesWindow() -> NSWindow {
    let host = NSHostingController(rootView: PreferencesView())
    host.sizingOptions = []   // the window's size is fixed below; don't let SwiftUI resize it
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 580),
                     styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                     backing: .buffered, defer: false)
    w.contentViewController = host
    w.titlebarAppearsTransparent = true
    w.titleVisibility = .hidden
    w.isMovableByWindowBackground = true
    w.isReleasedWhenClosed = false
    w.setContentSize(NSSize(width: 800, height: 580))
    w.center()
    return w
}

// MARK: - Shell

struct PreferencesView: View {
    @ObservedObject var nav = PrefsNavigation.shared

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $nav.tab)
                .frame(width: 214)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(nav.tab.title).font(.system(size: 26, weight: .bold)).tracking(-0.3)
                        if !nav.tab.subtitle.isEmpty {
                            Text(nav.tab.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        switch nav.tab {
                        case .general: GeneralPage()
                        case .appearance: AppearancePage()
                        case .windows: WindowsPage()
                        case .permissions: PermissionsPage()
                        case .about: AboutPage()
                        }
                    }
                    .id(nav.tab)
                    .transition(.opacity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 46)
                .padding(.bottom, 32)
                .animation(.easeOut(duration: 0.18), value: nav.tab)
            }
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        }
        .frame(width: 800, height: 580)
        .ignoresSafeArea()
    }
}

private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

private struct Sidebar: View {
    @Binding var selection: PrefsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Whisk").font(.system(size: 14.5, weight: .semibold))
                    Text("Window switcher").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 46)
            .padding(.bottom, 20)

            ForEach(PrefsTab.allCases) { tab in
                SidebarItem(tab: tab, selected: selection == tab) {
                    withAnimation(.snappy(duration: 0.2)) { selection = tab }
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(.pink.opacity(0.8))
                Text("Free. No subscriptions.").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.bottom, 16)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(VisualEffect(material: .sidebar).ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5).ignoresSafeArea()
        }
    }
}

private struct SidebarItem: View {
    let tab: PrefsTab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconBadge(symbol: tab.symbol, tint: tab.tint, size: 24)
                Text(tab.title).font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.10 : (hovering ? 0.05 : 0))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Building blocks

private struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 28
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(tint.opacity(0.16)))
    }
}

private struct Hairline: View {
    var inset: CGFloat = 14
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5).padding(.leading, inset)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

private struct Section<Content: View>: View {
    let title: String
    let footer: String?
    let content: Content
    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.footer = footer; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            Card { content }
            if let footer {
                Text(footer).font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct Row<Control: View>: View {
    var symbol: String? = nil
    var tint: Color = .gray
    var appIcon: NSImage? = nil
    let title: String
    var subtitle: String? = nil
    var divider = true
    @ViewBuilder let control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let symbol { IconBadge(symbol: symbol, tint: tint) }
                if let appIcon { Image(nsImage: appIcon).resizable().frame(width: 28, height: 28) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5, weight: .medium))
                    if let subtitle { Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 12)
                control
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            if divider { Hairline(inset: symbol == nil && appIcon == nil ? 14 : 54) }
        }
    }
}

/// A sliding-pill segmented control (replaces the stock segmented Picker, which looks dated).
private struct Segmented<T: Hashable>: View {
    let options: [T]
    let title: (T) -> String
    @Binding var selection: T
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Text(title(option))
                    .font(.system(size: 12.5, weight: on ? .semibold : .medium))
                    .foregroundStyle(on ? Color.primary : Color.secondary)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.13))
                                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy(duration: 0.22)) { selection = option } }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

private struct KeyCap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 6)
            .frame(minWidth: 24, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 0, y: 1)
    }
}

private struct KeyCombo: View {
    let keys: [String]
    var body: some View {
        HStack(spacing: 4) { ForEach(Array(keys.enumerated()), id: \.offset) { KeyCap(label: $0.element) } }
    }
}

/// Compact two-column list of keys that work while the switcher is open.
private struct ShortcutGrid: View {
    let items: [(String, [String])]
    var body: some View {
        let left = stride(from: 0, to: items.count, by: 2).map { items[$0] }
        let right = stride(from: 1, to: items.count, by: 2).map { items[$0] }
        HStack(alignment: .top, spacing: 0) {
            column(left)
            Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 0.5)
            column(right)
        }
    }
    private func column(_ rows: [(String, [String])]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack {
                    Text(r.0).font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 8)
                    KeyCombo(keys: r.1)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                if i < rows.count - 1 { Hairline() }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - General

private struct GeneralPage: View {
    @ObservedObject var settings = Settings.shared

    var body: some View {
        let mod = settings.triggerModifier.symbol
        Section("Shortcut", footer: settings.triggerModifier == .command
                ? "Command replaces the macOS app switcher (⌘Tab) while Whisk is running." : nil) {
            Row(symbol: "keyboard.fill", tint: .indigo, title: "Hold to switch", subtitle: "Hold, then press Tab.") {
                Segmented(options: Array(TriggerModifier.allCases), title: { $0.shortTitle }, selection: $settings.triggerModifier)
            }
            Row(title: "All windows", subtitle: "Cycle through every open window.") { KeyCombo(keys: [mod, "Tab"]) }
            Row(title: "Go backwards") { KeyCombo(keys: [mod, "⇧", "Tab"]) }
            Row(title: "Current app only", subtitle: "Cycle through windows of the front app.", divider: false) { KeyCombo(keys: [mod, "`"]) }
        }

        Section("While the switcher is open", footer: "Releasing \(mod) switches to the highlighted window. Hovering with the mouse also selects.") {
            ShortcutGrid(items: [
                ("Move selection", ["←", "→", "↑", "↓"]),
                ("Switch to window", ["↩"]),
                ("Cancel", ["esc"]),
                ("Quit app", ["Q"]),
                ("Close window", ["W"]),
                ("Minimize", ["M"]),
                ("Hide app", ["H"]),
            ])
        }

        Section("Behavior") {
            Row(symbol: "power", tint: .green, title: "Launch at login", subtitle: "Start Whisk when you log in. Works best from the Applications folder.") {
                Toggle("", isOn: $settings.launchAtLogin).toggleStyle(.switch).labelsHidden()
            }
            Row(symbol: "menubar.rectangle", tint: .blue, title: "Show menu bar icon", subtitle: "If hidden, open Whisk again to reach these settings.") {
                Toggle("", isOn: $settings.showMenuBarIcon).toggleStyle(.switch).labelsHidden()
            }
            Row(symbol: "timer", tint: .orange, title: "Panel delay", subtitle: "A quick tap switches instantly, without showing the panel.", divider: false) {
                HStack(spacing: 8) {
                    Slider(value: $settings.showDelay, in: 0...0.5, step: 0.05).frame(width: 130)
                    Text(settings.showDelay == 0 ? "Instant" : "\(Int(settings.showDelay * 1000)) ms")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                }
            }
        }
    }
}

private extension TriggerModifier {
    var shortTitle: String {
        switch self {
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .command: return "⌘ Command"
        }
    }
}

// MARK: - Appearance

private struct AppearancePage: View {
    @ObservedObject var settings = Settings.shared

    var body: some View {
        SwitcherPreview()

        Section("Layout") {
            Row(symbol: "arrow.up.left.and.arrow.down.right", tint: .teal, title: "Size", subtitle: "Bigger tiles show more detail; many windows shrink to fit.") {
                Segmented(options: Array(TileSize.allCases), title: { $0.title }, selection: $settings.tileSize)
            }
            Row(symbol: "photo.fill", tint: .pink, title: "Window previews", subtitle: "Show a live picture of each window instead of just the app icon.") {
                Toggle("", isOn: $settings.showThumbnails).toggleStyle(.switch).labelsHidden()
            }
            Row(symbol: "textformat", tint: .gray, title: "Window titles", divider: false) {
                Toggle("", isOn: $settings.showTitles).toggleStyle(.switch).labelsHidden()
            }
        }

        Section("Experimental", footer: liquidFooter) {
            Row(symbol: "drop.fill", tint: .cyan, title: "Liquid Glass design",
                subtitle: "A glass panel where the selection flows smoothly from one window to the next.", divider: settings.liquidGlass) {
                Toggle("", isOn: $settings.liquidGlass).toggleStyle(.switch).labelsHidden()
            }
            if settings.liquidGlass {
                Row(symbol: "circle.lefthalf.filled", tint: .indigo, title: "Glass clarity",
                    subtitle: "Slide toward Clear to see through the glass, or toward Frosted for a softer blur.", divider: false) {
                    HStack(spacing: 8) {
                        Text("Clear").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $settings.glassFrost, in: 0...1).frame(width: 140)
                        Text("Frosted").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        Section("Theme") {
            HStack(spacing: 14) {
                ForEach(ThemeChoice.allCases) { choice in
                    ThemeCard(choice: choice, selected: settings.theme == choice)
                        .onTapGesture { settings.theme = choice }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}

private extension AppearancePage {
    var liquidFooter: String? {
        if #available(macOS 26.0, *) { return "Turn off to go back to the classic design." }
        return "Real Liquid Glass needs macOS 26 or later. On this version you get a frosted-glass look."
    }
}

private struct SwitcherPreview: View {
    @ObservedObject var settings = Settings.shared
    @Environment(\.colorScheme) private var systemScheme
    @State private var model: SwitcherModel = {
        let m = SwitcherModel()
        m.windows = makeSampleWindows(count: 3)
        m.selected = 1
        return m
    }()
    @State private var panelSize = CGSize(width: 600, height: 240)

    private let boxSize = CGSize(width: 536, height: 270)

    private var scheme: ColorScheme {
        switch settings.theme {
        case .system: return systemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The panel is laid out at its real size, then scaled down to fit the preview box.
    private var fitScale: CGFloat { min(1, (boxSize.width - 48) / panelSize.width, (boxSize.height - 48) / panelSize.height) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.85), Color(red: 0.55, green: 0.35, blue: 0.75), Color(red: 0.95, green: 0.55, blue: 0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            SwitcherView(model: model, actions: TileActions(hover: { _ in }, click: { _ in }, close: { _ in }, minimize: { _ in }, fullscreen: { _ in }))
                .frame(width: panelSize.width, height: panelSize.height)
                .background {
                    // The liquid panel draws its own glass; a second fill would poke out at its corners.
                    if !settings.liquidGlass {
                        RoundedRectangle(cornerRadius: Layout.corner, style: .continuous)
                            .fill(scheme == .dark ? Color(white: 0.16, opacity: 0.92) : Color(white: 0.96, opacity: 0.92))
                    }
                }
                .environment(\.colorScheme, scheme)
                .scaleEffect(fitScale)
                .frame(width: panelSize.width * fitScale, height: panelSize.height * fitScale)
                .allowsHitTesting(false)
        }
        .frame(height: boxSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .onAppear(perform: relayout)
        .onReceive(settings.objectWillChange.receive(on: RunLoop.main)) { _ in relayout() }
        // Step the selection along so the preview shows how switching feels in the chosen design.
        .onReceive(Timer.publish(every: 1.6, on: .main, in: .common).autoconnect()) { _ in
            model.selected = (model.selected + 1) % max(1, model.windows.count)
        }
    }

    private func relayout() { panelSize = model.layout(maxWidth: 2000, maxHeight: 1000) }
}

private struct ThemeCard: View {
    let choice: ThemeChoice
    let selected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                switch choice {
                case .light: mini(dark: false)
                case .dark: mini(dark: true)
                case .system:
                    HStack(spacing: 0) {
                        mini(dark: false).frame(width: 55).clipped()
                        mini(dark: true).frame(width: 55, alignment: .trailing).clipped()
                    }
                }
            }
            .frame(width: 110, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: selected ? 2.5 : 0.5))
            .padding(2)
            Text(choice.title).font(.callout).fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .contentShape(Rectangle())
    }

    private func mini(dark: Bool) -> some View {
        ZStack {
            Color(white: dark ? 0.14 : 0.94)
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: dark ? 0.32 : 0.78))
                        .frame(width: 26, height: 34)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(i == 1 ? Color.accentColor : .clear, lineWidth: 1.5))
                }
            }
        }
        .frame(width: 110, height: 68)
    }
}

// MARK: - Windows

private struct WindowsPage: View {
    @ObservedObject var settings = Settings.shared

    var body: some View {
        Section("Show windows") {
            Row(symbol: "minus.circle.fill", tint: .yellow, title: "Minimized", subtitle: "Windows you've minimized to the Dock.") {
                Toggle("", isOn: $settings.showMinimized).toggleStyle(.switch).labelsHidden()
            }
            Row(symbol: "eye.slash.fill", tint: .gray, title: "Hidden apps", subtitle: "Apps hidden with ⌘H.") {
                Toggle("", isOn: $settings.showHiddenApps).toggleStyle(.switch).labelsHidden()
            }
            Row(symbol: "arrow.up.left.and.arrow.down.right", tint: .green, title: "Fullscreen", subtitle: "Apps in their own fullscreen Space.") {
                Toggle("", isOn: $settings.showFullscreen).toggleStyle(.switch).labelsHidden()
            }
            Row(symbol: "square.on.square", tint: .blue, title: "Other Spaces", subtitle: "Windows on your other desktops.", divider: false) {
                Toggle("", isOn: $settings.showOtherSpaces).toggleStyle(.switch).labelsHidden()
            }
        }

        Section("Screens") {
            Row(symbol: "display", tint: .indigo, title: "Show windows from", divider: false) {
                Segmented(options: Array(ScreenFilter.allCases), title: { $0.shortTitle }, selection: $settings.screenFilter)
            }
        }

        Section("Excluded apps", footer: "Windows of these apps never appear in the switcher.") {
            ForEach(settings.excludedBundleIDs.sorted(), id: \.self) { id in
                Row(appIcon: Self.icon(for: id), title: Self.name(for: id)) {
                    Button { settings.excludedBundleIDs.removeAll { $0 == id } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary).imageScale(.large)
                    }
                    .buttonStyle(.plain)
                }
            }
            if settings.excludedBundleIDs.isEmpty {
                Row(title: "No excluded apps", subtitle: "Whisk shows windows from every app.") { EmptyView() }
            }
            Menu {
                ForEach(runningApps, id: \.processIdentifier) { app in
                    Button(app.localizedName ?? app.bundleIdentifier ?? "App") { add(app.bundleIdentifier) }
                }
                Divider()
                Button("Choose from disk…", action: chooseFromDisk)
            } label: {
                Label("Add application…", systemImage: "plus.circle.fill")
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && !settings.excludedBundleIDs.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func add(_ id: String?) {
        guard let id, !settings.excludedBundleIDs.contains(id) else { return }
        settings.excludedBundleIDs.append(id)
    }

    private func chooseFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { add(Bundle(url: url)?.bundleIdentifier) }
    }

    private static func appURL(_ id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
    static func name(for id: String) -> String {
        appURL(id).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
    }
    static func icon(for id: String) -> NSImage {
        appURL(id).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage()
    }
}

private extension ScreenFilter {
    var shortTitle: String { self == .all ? "All screens" : "Screen with mouse" }
}

// MARK: - Permissions

private struct PermissionsPage: View {
    @ObservedObject var state = PermissionState.shared
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Section("Required by macOS", footer: "After enabling a permission in System Settings, Whisk may need a relaunch to notice it.") {
            Row(symbol: "hand.raised.fill", tint: .blue, title: "Accessibility",
                subtitle: "Detects the shortcut and raises, closes and minimizes windows.") {
                status(state.accessibility, grant: state.requestAccessibility)
            }
            Row(symbol: "record.circle.fill", tint: .red, title: "Screen Recording",
                subtitle: "Shows window previews and titles. Without it you only get app icons.", divider: false) {
                status(state.screenRecording, grant: state.requestScreenRecording)
            }
        }
        Button { relaunchApp() } label: { Label("Relaunch Whisk", systemImage: "arrow.clockwise") }
            .controlSize(.regular)
        Color.clear.frame(height: 0)
            .onReceive(timer) { _ in state.refresh() }
    }

    @ViewBuilder
    private func status(_ granted: Bool, grant: @escaping () -> Void) -> some View {
        if granted {
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.green.opacity(0.15)))
        } else {
            Button("Grant…", action: grant).buttonStyle(.borderedProminent).controlSize(.small)
        }
    }
}

// MARK: - About

private struct AboutPage: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 88, height: 88)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            VStack(spacing: 6) {
                Text("Whisk").font(.system(size: 24, weight: .bold)).tracking(-0.3)
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            Text("Every feature, free. No subscriptions, no accounts, no tracking.")
                .font(.system(size: 13)).multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                link("Website", "safari", "https://nithinkr080.github.io/Whisk/")
                link("GitHub", "chevron.left.forwardslash.chevron.right", "https://github.com/nithinkr080/Whisk")
                link("Report an issue", "exclamationmark.bubble", "https://github.com/nithinkr080/Whisk/issues")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)

        Section("Tips") {
            Row(symbol: "hand.tap.fill", tint: .blue, title: "Quick tap", subtitle: "Tap the shortcut once to jump to your previous window.") { EmptyView() }
            Row(symbol: "cursorarrow.motionlines", tint: .purple, title: "Hover for controls", subtitle: "Hover a tile to close, minimize or fullscreen that window.") { EmptyView() }
            Row(symbol: "square.stack.3d.up.fill", tint: .green, title: "Works across Spaces", subtitle: "Pick a window in a fullscreen app and Whisk takes you to it.", divider: false) { EmptyView() }
        }
    }

    private func link(_ title: String, _ symbol: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
