import Foundation
import SwiftUI

/// Manages the AudioEngine lifecycle.
/// Auto-starts on app launch. Never blocks UI with permission prompts.
@MainActor
final class AudioEngineManager: ObservableObject {
    static let shared = AudioEngineManager()

    private var engine: AudioEngine?
    @Published var activeApps: [AudioApp] = []
    @Published var engineStarted = false
    private var appPollingTimer: Timer?

    private init() {}

    // MARK: - Lifecycle

    /// Call from AppDelegate on launch. Directly starts engine, no permission checks.
    func startOnLaunch() {
        guard engine == nil else { return }
        startEngine()
    }

    /// Called from MorePanelView onAppear — ensures engine is started
    func start() {
        if engine == nil {
            startEngine()
        }
    }

    private func startEngine() {
        guard engine == nil else { return }

        guard #available(macOS 14.2, *) else {
            return
        }

        let e = AudioEngine()
        engine = e
        engineStarted = true

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
        engine = nil
        activeApps = []
        engineStarted = false
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
