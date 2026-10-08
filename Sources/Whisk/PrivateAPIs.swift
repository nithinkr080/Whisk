import ApplicationServices
import CoreGraphics
import Darwin

// Private / undocumented symbols that every macOS window switcher relies on.
// They have been stable for many macOS releases.

/// Maps an Accessibility window element to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("GetProcessForPID")
func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

private let skyLight: UnsafeMutableRawPointer? =
    dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

private func skyLightSymbol<T>(_ name: String, as: T.Type) -> T? {
    guard let skyLight, let sym = dlsym(skyLight, name) else { return nil }
    return unsafeBitCast(sym, to: T.self)
}

private typealias SetFrontFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
private typealias PostEventFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

private let setFrontFn = skyLightSymbol("_SLPSSetFrontProcessWithOptions", as: SetFrontFn.self)
private let postEventFn = skyLightSymbol("SLPSPostEventRecordTo", as: PostEventFn.self)

/// True when the SkyLight window-focus calls are available on this macOS version.
var skyLightFocusAvailable: Bool { setFrontFn != nil && postEventFn != nil }

/// Brings a process (and a specific window, even on another Space) to the front.
@discardableResult
func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: CGWindowID, _ mode: UInt32) -> CGError {
    setFrontFn?(psn, wid, mode) ?? .failure
}

@discardableResult
func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError {
    postEventFn?(psn, bytes) ?? .failure
}

/// Enables / disables a system keyboard shortcut (used to take over ⌘Tab).
@_silgen_name("CGSSetSymbolicHotKeyEnabled")
func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: Bool) -> CGError

// Spaces (virtual desktops, including fullscreen apps, which each get their own Space)
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray

@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ wids: CFArray) -> CFArray

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: Int32) -> Int

/// Moves windows onto one Space (used to keep the switcher panel on the Space the user is looking at).
@_silgen_name("CGSMoveWindowsToManagedSpace")
func CGSMoveWindowsToManagedSpace(_ cid: Int32, _ wids: CFArray, _ space: Int)

@_silgen_name("CGSManagedDisplaySetCurrentSpace")
func CGSManagedDisplaySetCurrentSpace(_ cid: Int32, _ display: CFString, _ space: Int)

/// Builds an Accessibility element from a raw (pid, element id) token. Windows on other Spaces are not
/// returned by kAXWindowsAttribute, but they can be reached by probing element ids.
@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?
