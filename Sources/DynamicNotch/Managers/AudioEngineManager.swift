import Foundation
import SwiftUI
import ApplicationServices
import Combine

/// Manages the AudioEngine lifecycle. Created lazily when the More panel opens.
/// Exposes active audio apps and per-app volume/mute controls for the UI.
@MainActor
final class AudioEngineManager: ObservableObject {
    static let shared = AudioEngineManager()

    private var engine: AudioEngine?
    @Published var activeApps: [AudioApp] = []
    @Published var engineStatus: String? = nil
    private var appPollingTimer: Timer?

    private init() {}

    // MARK: - Lifecycle

    /// Start the audio engine. Safe to call multiple times — only creates once.
    func start() {
        guard engine == nil else { return }

        // Check accessibility permission (required for process taps)
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        )
        if !trusted {
            engineStatus = "需要辅助功能权限"
            return
        }

        if #available(macOS 14.2, *) {
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
        } else {
            engineStatus = "需要 macOS 14.2+"
        }
    }

    /// Stop the audio engine and release resources.
    func stop() {
        appPollingTimer?.invalidate()
        appPollingTimer = nil
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
