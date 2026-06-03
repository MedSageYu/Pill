import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = NotchWindowController()
        NotificationManager.shared.startListening()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AudioEngineManager.shared.stop()  // 清理 process taps
        windowController?.destroy()
    }
}