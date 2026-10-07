import CoreGraphics

/// A snapshot of the Spaces on all displays. Fullscreen apps live in their own Space (type 4), and
/// windows in Spaces other than the visible ones are invisible to the Accessibility API.
struct SpaceSnapshot {
    private static let fullscreenType = 4
    private let cid = CGSMainConnectionID()
    private(set) var visible = Set<Int>()
    private var types = [Int: Int]()
    private var spaceDisplays = [Int: String]()

    init() {
        let displays = (CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]]) ?? []
        for d in displays {
            if let cur = (d["Current Space"] as? [String: Any])?["id64"] as? Int { visible.insert(cur) }
            let display = d["Display Identifier"] as? String
            for s in (d["Spaces"] as? [[String: Any]]) ?? [] {
                if let id = s["id64"] as? Int, let type = s["type"] as? Int {
                    types[id] = type
                    spaceDisplays[id] = display
                }
            }
        }
    }

    /// Spaces the window belongs to. Empty for helper/overlay windows that no Space owns.
    func spaces(of wid: CGWindowID) -> [Int] {
        (CGSCopySpacesForWindows(cid, 7, [Int(wid)] as CFArray) as? [Int]) ?? []
    }

    func display(of space: Int) -> String? { spaceDisplays[space] }

    func isFullscreenSpace(_ id: Int) -> Bool { types[id] == Self.fullscreenType }
}

enum SpaceSwitcher {
    /// Makes `space` the visible Space of its display (what clicking it in Mission Control does).
    static func show(space: Int, on display: String) {
        CGSManagedDisplaySetCurrentSpace(CGSMainConnectionID(), display as CFString, space)
    }
}
