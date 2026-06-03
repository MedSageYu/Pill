import Foundation
import SwiftUI

/// Manages the AudioEngine lifecycle for per-app audio control.
/// Only starts when the user opens the "音频" tab. Properly cleans up on stop.
@MainActor
final class AudioEngineManager: ObservableObject {
    static let shared = AudioEngineManager()

    private var engine: AudioEngine?
    @Published var activeApps: [AudioApp] = []
    @Published var engineRunning = false
    private var appPollingTimer: Timer?

    private init() {}

    // MARK: - Lifecycle

    /// Start the audio engine and begin monitoring apps.
    /// Only call when user opens the "音频" tab.
    func start() {
        guard engine == nil else { return }
        guard #available(macOS 14.2, *) else { return }

        let e = AudioEngine()
        engine = e
        e.start()  // ← CRITICAL: actually starts processMonitor + deviceMonitor
        engineRunning = true

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
    }

    /// Stop the audio engine and clean up all process taps.
    /// MUST be called before app exit to avoid residual taps.
    func stop() {
        appPollingTimer?.invalidate()
        appPollingTimer = nil
        engine?.stop()  // ← CRITICAL: invalidates all process taps
        engine = nil
        activeApps = []
        engineRunning = false
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
