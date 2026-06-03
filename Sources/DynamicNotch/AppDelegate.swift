import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = NotchWindowController()
        NotificationManager.shared.startListening()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.destroy()
    }
}
