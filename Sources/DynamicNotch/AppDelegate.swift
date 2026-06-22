import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NotchWindowController?
    private var updateCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = NotchWindowController()
        NotificationManager.shared.startListening()
        startUpdateCheckCycle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateCheckTimer?.invalidate()
        windowController?.destroy()
    }

    // MARK: - 每日自动检测更新

    private func startUpdateCheckCycle() {
        // 启动后延迟 30s 首次检测（等网络就绪）
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.performUpdateCheck()
        }
        // 每 24 小时检测一次
        updateCheckTimer = Timer.scheduledTimer(
            withTimeInterval: 86400, repeats: true
        ) { [weak self] _ in
            self?.performUpdateCheck()
        }
    }

    private func performUpdateCheck() {
        print("[UpdateChecker] 🔍 开始自动检测更新...")
        UpdateChecker.shared.check { [weak self] status in
            switch status {
            case .updateAvailable(let current, let latest, let url):
                print("[UpdateChecker] 📦 发现新版本: \(current) → \(latest)")
                self?.postUpdateNotification(
                    current: current, latest: latest, url: url)
                // 同时通过 NotchViewModel 展示在灵动岛
                let noti = IncomingNotification(
                    title: "发现新版本 v\(latest)",
                    subtitle: "当前 v\(current)，点击下载",
                    appBundleID: "",
                    appName: "Pill",
                    timestamp: Date()
                )
                DispatchQueue.main.async {
                    NotchViewModel.shared.receiveNotification(noti)
                }
            case .error(let msg):
                print("[UpdateChecker] ⚠️ 检测失败: \(msg)")
            case .upToDate:
                print("[UpdateChecker] ✅ 已是最新 v\(UpdateChecker.shared.currentVersion)")
            default:
                break
            }
        }
    }

    private func postUpdateNotification(current: String, latest: String, url: URL?) {
        let content = UNMutableNotificationContent()
        content.title = "Pill 有更新"
        content.subtitle = "当前 v\(current) → v\(latest)"
        content.body = url?.absoluteString ?? "前往 GitHub 下载"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "pill-update-\(latest)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[UpdateChecker] 通知发送失败: \(error.localizedDescription)")
            }
        }
    }
}
