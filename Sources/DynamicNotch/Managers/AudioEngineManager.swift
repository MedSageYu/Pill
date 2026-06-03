import Foundation
import SwiftUI
import ApplicationServices
import Combine

/// Manages the AudioEngine lifecycle. Auto-starts when the app launches.
/// Exposes active audio apps and per-app volume/mute controls for the UI.
@MainActor
final class AudioEngineManager: ObservableObject {
    static let shared = AudioEngineManager()

    private var engine: AudioEngine?
    @Published var activeApps: [AudioApp] = []
    @Published var engineStatus: String? = nil
    private var appPollingTimer: Timer?
    private var permissionCheckTimer: Timer?
    private var permissionDialogShown = false  // prevent repeated permission prompts

    private init() {}

    // MARK: - Lifecycle

    /// Call this once from AppDelegate on app launch.
    /// If accessibility permission is not granted, it will prompt the user ONCE
    /// and keep checking silently until permission is granted.
    func startOnLaunch() {
        // Already running or already polling — don't prompt again
        guard engine == nil, permissionCheckTimer == nil else { return }

        if AXIsProcessTrusted() {
            startEngine()
            return
        }

        // Show permission dialog only once
        if !permissionDialogShown {
            permissionDialogShown = true
            engineStatus = "需要辅助功能权限"
            AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            )
        }

        // Poll silently every 3 seconds until permission is granted
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if AXIsProcessTrusted() {
                    self.permissionCheckTimer?.invalidate()
                    self.permissionCheckTimer = nil
                    self.permissionDialogShown = false
                    self.startEngine()
                }
            }
        }
    }

    /// Called from MorePanelView onAppear — just ensures engine is started
    func start() {
        if engine == nil {
            startOnLaunch()
        }
    }

    private func startEngine() {
        guard engine == nil else { return }

        guard #available(macOS 14.2, *) else {
            engineStatus = "需要 macOS 14.2+"
            return
        }

        let e = AudioEngine()
        engine = e
        engineStatus = nil

        // Poll for active apps every 1 second
        appPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let engine = self.engine else { return }
                let apps = engine.processMonitor.activeApps
                if apps != self.activeApps {
                    self.activeApps = apps
                }
            }
        }

        // Get initial app list
        activeApps = e.processMonitor.activeApps
    }

    func stop() {
        appPollingTimer?.invalidate()
        appPollingTimer = nil
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        engine = nil
        activeApps = []
    }

    // MARK: - Per-App Controls

    func setVolume(for app: AudioApp, to volume: Float) {
        engine?.setVolume(for: app, to: volume)
    }

    func toggleMute(for app: AudioApp) {
        engine?.toggleMute(for: app)
    }

    func currentVolume(for app: AudioApp) -> Float {
        engine?.currentVolume(for: app) ?? 1.0
    }

    func isMuted(for app: AudioApp) -> Bool {
        engine?.isMuted(for: app) ?? false
    }
}
