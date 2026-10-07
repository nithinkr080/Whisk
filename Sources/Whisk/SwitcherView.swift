import SwiftUI

struct TileActions {
    let hover: (Int) -> Void
    let click: (Int) -> Void
    let close: (Int) -> Void
    let minimize: (Int) -> Void
    let fullscreen: (Int) -> Void
}

/// Picks the classic or the experimental Liquid Glass presentation based on the preference.
struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @ObservedObject var settings = Settings.shared
    let actions: TileActions
    var body: some View {
        if settings.liquidGlass {
            LiquidSwitcherView(model: model, actions: actions)
        } else {
            ClassicSwitcherView(model: model, actions: actions)
        }
    }
}

// MARK: - Classic

struct ClassicSwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let actions: TileActions

    var body: some View {
        Group {
            if model.needsScroll {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) { grid }
                        .onChange(of: model.selected) { _, new in
                            guard model.windows.indices.contains(new) else { return }
                            proxy.scrollTo(model.windows[new].id)
                        }
                }
            } else {
                grid
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Layout.corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                .allowsHitTesting(false)
        )
    }

    private var grid: some View {
        VStack(spacing: Layout.gap) {
            ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Layout.gap) {
                    ForEach(row, id: \.self) { index in
                        if model.windows.indices.contains(index) {
                            TileView(window: model.windows[index], model: model, index: index,
                                     selected: index == model.selected, actions: actions)
                                .id(model.windows[index].id)
                        }
                    }
                }
            }
        }
        .padding(Layout.pad)
    }
}

// MARK: - Liquid Glass (experimental)

enum LiquidMetrics {
    static let panelCorner: CGFloat = 38
    static let selectionCorner: CGFloat = 24
    static let spring = Animation.spring(response: 0.46, dampingFraction: 0.72)
}

struct LiquidSwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let actions: TileActions

    var body: some View {
        Group {
            if model.needsScroll {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) { grid }
                        .onChange(of: model.selected) { _, new in
                            guard model.windows.indices.contains(new) else { return }
                            withAnimation(LiquidMetrics.spring) { proxy.scrollTo(model.windows[new].id) }
                        }
                }
            } else {
                grid
            }
        }
        .background { LiquidPanelBackground() }
    }

    private var grid: some View {
        VStack(spacing: Layout.gap) {
            ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Layout.gap) {
                    ForEach(row, id: \.self) { index in
                        if model.windows.indices.contains(index) {
                            TileView(window: model.windows[index], model: model, index: index,
                                     selected: index == model.selected, actions: actions, liquid: true)
                                .id(model.windows[index].id)
                        }
                    }
                }
            }
        }
        // The glass lives on its own layer *behind* the tiles, so previews stay crisp on top of it, and a single
        // shape glides between tile positions. Positions come straight from the layout: measuring the tiles
        // instead created a feedback loop (the rising tile changes its measured frame, which re-renders the
        // big glass panel every frame) that dropped most frames with many windows.
        .background { LiquidSelectionLayer(frame: model.frame(of: model.selected)) }
        .padding(Layout.pad)
    }
}

/// One glass shape that flows to the selected tile: a spring moves and resizes it, so it overshoots and settles
/// like a drop of liquid, the way the selection in Apple's tab bars does.
struct LiquidSelectionLayer: View {
    let frame: CGRect?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let f = frame {
                LiquidSelectionShape()
                    .frame(width: f.width * 1.04, height: f.height * 1.04)
                    .offset(x: f.minX - f.width * 0.02, y: f.minY - f.height * 0.02)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(LiquidMetrics.spring, value: frame)
        .allowsHitTesting(false)
    }
}

/// Light catching the edge of the glass: bright where it faces the light, fading through the middle.
private func glassRim(opacity: Double = 1) -> LinearGradient {
    LinearGradient(colors: [Color.white.opacity(0.70 * opacity), Color.white.opacity(0.06 * opacity),
                            Color.white.opacity(0.28 * opacity), Color.white.opacity(0.55 * opacity)],
                   startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Tint of the liquid selection: a faint cool white, like light through water. It deliberately ignores the
/// user's macOS accent colour (which made the selection green on some Macs).
enum LiquidTint {
    static let water = Color(red: 0.80, green: 0.93, blue: 1.0)
}

struct LiquidPanelBackground: View {
    @ObservedObject var settings = Settings.shared

    var body: some View {
        let frost = min(max(settings.glassFrost, 0), 1)
        let shape = RoundedRectangle(cornerRadius: LiquidMetrics.panelCorner, style: .continuous)
        ZStack {
            if #available(macOS 26.0, *) {
                // Clear glass refracts what is behind it. Frostedness is dialled in by laying a blur and a
                // touch of tint over it, so the slider sweeps smoothly from crystal clear to frosted.
                Color.clear.glassEffect(.clear.tint(Color.black.opacity(0.03 + 0.03 * frost)), in: .rect(cornerRadius: LiquidMetrics.panelCorner))
            }
            shape.fill(.ultraThinMaterial).opacity(0.85 * frost)
            // Rim light and edge glow. These are big gradients; drawn by SwiftUI's default renderer they are
            // shaded on the CPU and repainted on every animation frame, so they go through the GPU instead.
            ZStack {
                shape.strokeBorder(glassRim(opacity: 1.0 - 0.35 * frost), lineWidth: 1.3)
                shape.strokeBorder(Color.white.opacity(0.16 * (1 - frost) + 0.06), lineWidth: 5).blur(radius: 5).mask(shape)
            }
            .drawingGroup()
        }
    }
}

struct LiquidSelectionShape: View {
    @ObservedObject var settings = Settings.shared

    var body: some View {
        let frost = min(max(settings.glassFrost, 0), 1)
        let shape = RoundedRectangle(cornerRadius: LiquidMetrics.selectionCorner, style: .continuous)
        ZStack {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.clear.tint(LiquidTint.water.opacity(0.20 + 0.10 * frost)), in: .rect(cornerRadius: LiquidMetrics.selectionCorner))
            } else {
                shape.fill(.thinMaterial)
            }
            shape.fill(.thinMaterial).opacity(0.4 * frost)
            ZStack {
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.0)], startPoint: .top, endPoint: .center))
                shape.strokeBorder(glassRim(), lineWidth: 1.5)
            }
            .drawingGroup()
        }
        .shadow(color: LiquidTint.water.opacity(0.30), radius: 14, y: 5)
    }
}

// MARK: - Tile

struct TileView: View {
    @ObservedObject var window: WindowInfo
    @ObservedObject var settings = Settings.shared
    let model: SwitcherModel
    let index: Int
    let selected: Bool
    let actions: TileActions
    var liquid = false
    @State private var hovering = false

    var body: some View {
        let tile = model.tileSize(window)
        let thumb = model.thumbSize(window)
        VStack(spacing: 8) {
            if settings.showThumbnails {
                thumbnail(thumb)
            } else {
                iconOnly(thumb)
            }
            if settings.showTitles {
                Text(window.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(settings.showThumbnails ? 1 : 2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(liquid ? 0.35 : 0), radius: liquid ? 2 : 0, y: 1)
                    .frame(width: thumb.width)
            }
        }
        .padding(Layout.tilePad)
        .frame(width: tile.width, height: tile.height, alignment: .top)
        .modifier(SelectionChrome(selected: selected, liquid: liquid))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { actions.click(index) }
        .onHover { inside in
            hovering = inside
            if inside { actions.hover(index) }
        }
    }

    private func thumbnail(_ size: CGSize) -> some View {
        ZStack {
            if let img = window.thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .opacity(window.isMinimized ? 0.55 : 1)
            } else {
                Color.primary.opacity(0.07)
                Image(nsImage: window.icon)
                    .resizable().scaledToFit()
                    .frame(width: size.height * 0.5, height: size.height * 0.5)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: liquid ? 16 : 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: liquid ? 16 : 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(liquid ? 0.22 : 0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 7, y: 3)
        .overlay(alignment: .bottomLeading) {
            if window.thumbnail != nil {
                Image(nsImage: window.icon)
                    .resizable()
                    .frame(width: 34, height: 34)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .padding(6)
            }
        }
        .overlay(alignment: .topTrailing) { badges.padding(6) }
        .overlay(alignment: .topLeading) {
            if hovering && window.axWindow != nil { trafficLights.padding(7) }
        }
    }

    private func iconOnly(_ size: CGSize) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: window.icon)
                .resizable().scaledToFit()
                .frame(width: size.height, height: size.height)
                .frame(width: size.width, height: size.height)
                .opacity(window.isMinimized || window.isAppHidden ? 0.55 : 1)
            badges
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topLeading) {
            if hovering && window.axWindow != nil { trafficLights }
        }
    }

    private var badges: some View {
        HStack(spacing: 4) {
            if window.isMinimized { badge("minus.circle.fill", .yellow) }
            if window.isFullscreen { badge("arrow.up.left.and.arrow.down.right.circle.fill", .green) }
        }
    }

    private func badge(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 15))
            .foregroundStyle(color, .black.opacity(0.55))
            .shadow(radius: 2)
    }

    private var trafficLights: some View {
        HStack(spacing: 6) {
            light(.red, "xmark") { actions.close(index) }
            light(.yellow, "minus") { actions.minimize(index) }
            light(.green, "arrow.up.left.and.arrow.down.right") { actions.fullscreen(index) }
        }
    }

    private func light(_ color: Color, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color)
                Image(systemName: symbol).font(.system(size: 7, weight: .heavy)).foregroundStyle(.black.opacity(0.6))
            }
            .frame(width: 15, height: 15)
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
        }
        .buttonStyle(.plain)
    }
}

/// Classic: a tinted rounded highlight with a border. Liquid: no chrome here (the glass shape flows
/// behind the tile instead); the selected tile just rises slightly.
private struct SelectionChrome: ViewModifier {
    let selected: Bool
    let liquid: Bool

    func body(content: Content) -> some View {
        if liquid {
            content.scaleEffect(selected ? 1.04 : 1).animation(LiquidMetrics.spring, value: selected)
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(selected ? Color.primary.opacity(0.17) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(selected ? Color.primary.opacity(0.45) : Color.clear, lineWidth: 1.5)
                )
        }
    }
}
