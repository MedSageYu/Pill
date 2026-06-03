import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = NotchWindowController()
        // 启动通知监听
        NotificationManager.shared.startListening()
        AudioEngineManager.shared.startOnLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.destroy()
    }
}