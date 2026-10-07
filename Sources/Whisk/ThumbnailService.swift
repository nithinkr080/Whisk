import AppKit
import ScreenCaptureKit

/// Captures window thumbnails. Cached thumbnails are shown instantly and refreshed in the background each
/// time the switcher opens.
///
/// The primary capture API is CGWindowListCreateImage: unlike ScreenCaptureKit it can read windows that are
/// not currently drawn (fullscreen apps and windows on other Spaces). It is deprecated, so it is looked up at
/// runtime and ScreenCaptureKit is used as the fallback if it ever disappears.
@MainActor
final class ThumbnailService {
    static let shared = ThumbnailService()
    private var cache = [CGWindowID: NSImage]()

    private struct Target { let id: CGWindowID; let width: CGFloat; let height: CGFloat }

    func apply(to windows: [WindowInfo], pixelHeight: CGFloat) {
        for w in windows { if let c = cache[w.id] { w.thumbnail = c } }
        guard CGPreflightScreenCaptureAccess() else { return }
        if cache.count > 150 {
            let live = Set(windows.map(\.id))
            cache = cache.filter { live.contains($0.key) }
        }

        let targets = windows.map { Target(id: $0.id, width: $0.bounds.width, height: $0.bounds.height) }
        Task { [weak self] in
            let height = Int(pixelHeight)
            for t in targets {
                guard let cg = await Self.capture(t, maxHeight: height) else { continue }
                let img = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
                guard let self else { return }
                self.cache[t.id] = img
                windows.first { $0.id == t.id }?.thumbnail = img
            }
        }
    }

    private nonisolated static func capture(_ t: Target, maxHeight: Int) async -> CGImage? {
        if let full = captureWindowList(t.id), full.width > 20, full.height > 20 {
            return downscale(full, maxHeight: maxHeight)
        }
        return await captureScreenCaptureKit(t, maxHeight: maxHeight)
    }

    // MARK: CGWindowListCreateImage

    private typealias CreateImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private nonisolated static let createImage: CreateImageFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(sym, to: CreateImageFn.self)
    }()

    nonisolated static func captureWindowList(_ id: CGWindowID) -> CGImage? {
        let includingWindow: UInt32 = 1 << 3          // kCGWindowListOptionIncludingWindow
        let ignoreFraming: UInt32 = 1 << 0            // kCGWindowImageBoundsIgnoreFraming
        let nominalResolution: UInt32 = 1 << 4        // kCGWindowImageNominalResolution
        return createImage?(.null, includingWindow, id, ignoreFraming | nominalResolution)?.takeRetainedValue()
    }

    private nonisolated static func downscale(_ image: CGImage, maxHeight: Int) -> CGImage? {
        guard image.height > maxHeight, maxHeight > 0 else { return image }
        let scale = CGFloat(maxHeight) / CGFloat(image.height)
        let width = max(1, Int(CGFloat(image.width) * scale))
        guard let ctx = CGContext(data: nil, width: width, height: maxHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: maxHeight))
        return ctx.makeImage() ?? image
    }

    // MARK: ScreenCaptureKit fallback

    private nonisolated static func captureScreenCaptureKit(_ t: Target, maxHeight: Int) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let sc = content.windows.first(where: { $0.windowID == t.id }),
              sc.frame.width > 1, sc.frame.height > 1 else { return nil }
        let factor = min(CGFloat(maxHeight) / sc.frame.height, 2)
        let cfg = SCStreamConfiguration()
        cfg.width = max(1, Int(sc.frame.width * factor))
        cfg.height = max(1, Int(sc.frame.height * factor))
        cfg.showsCursor = false
        cfg.scalesToFit = true
        return try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: sc), configuration: cfg)
    }
}
