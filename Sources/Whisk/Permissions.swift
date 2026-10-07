import SwiftUI
import ApplicationServices

@MainActor
final class PermissionState: ObservableObject {
    static let shared = PermissionState()
    @Published var accessibility = AXIsProcessTrusted()
    @Published var screenRecording = CGPreflightScreenCaptureAccess()

    var allGranted: Bool { accessibility && screenRecording }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        open("Privacy_Accessibility")
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        open("Privacy_ScreenCapture")
    }

    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

func relaunchApp() {
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}

struct PermissionsView: View {
    @ObservedObject var state = PermissionState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 34)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text("Welcome to Whisk").font(.title2.bold())
                    Text("Two macOS permissions are needed for the window switcher to work.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            row(title: "Accessibility", detail: "Detects the keyboard shortcut and raises, closes and minimizes windows.",
                granted: state.accessibility, action: state.requestAccessibility)
            row(title: "Screen Recording", detail: "Shows live window previews and titles. Without it you only get app icons.",
                granted: state.screenRecording, action: state.requestScreenRecording)
            Divider()
            HStack {
                Text("Tick Whisk in each list in System Settings. If a permission still shows as missing after enabling it, relaunch the app.")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("Relaunch Whisk", action: relaunchApp)
            }
        }
        .padding(24)
        .frame(width: 580)
    }

    private func row(title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2).foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted { Button("Grant…", action: action) }
        }
    }
}
