import AppKit
import SwiftUI

@main
struct VibeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = AudioEngine()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environmentObject(engine)
        } label: {
            Image(systemName: "waveform")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 仅菜单栏,不出现在 Dock
        NSApp.setActivationPolicy(.accessory)
    }
}
