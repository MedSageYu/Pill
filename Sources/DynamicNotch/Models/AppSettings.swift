import Foundation
import SwiftUI

// MARK: - 文件托盘自动清除策略

enum FileTrayClearPolicy: String, CaseIterable, Identifiable {
    case onDragOut   // 拖出就清除
    case after1Hour  // 1小时后自动清除
    case after2Hours // 2小时后自动清除
    case after1Day   // 一天后自动清除
    case never       // 永不清除

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onDragOut: "拖出就清除"
        case .after1Hour: "1小时后"
        case .after2Hours: "2小时后"
        case .after1Day: "一天后"
        case .never: "永不清除"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .after1Hour: 3600
        case .after2Hours: 7200
        case .after1Day: 86400
        default: nil
        }
    }
}

// MARK: - 应用设置

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var autoHideDelay: TimeInterval {
        didSet { UserDefaults.standard.set(autoHideDelay, forKey: "autoHideDelay") }
    }

    @Published var fileTrayClearPolicy: FileTrayClearPolicy {
        didSet {
            UserDefaults.standard.set(fileTrayClearPolicy.rawValue, forKey: "fileTrayClearPolicy")
        }
    }

    @Published var unlockCameraSnapshot: Bool {
        didSet { UserDefaults.standard.set(unlockCameraSnapshot, forKey: "unlockCameraSnapshot") }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.autoHideDelay = defaults.object(forKey: "autoHideDelay") as? TimeInterval ?? 4.0
        if let raw = defaults.string(forKey: "fileTrayClearPolicy"),
           let policy = FileTrayClearPolicy(rawValue: raw) {
            self.fileTrayClearPolicy = policy
        } else {
            self.fileTrayClearPolicy = .onDragOut
        }
        self.unlockCameraSnapshot = defaults.bool(forKey: "unlockCameraSnapshot")
    }

    func resetToDefaults() {
        autoHideDelay = 4.0
        fileTrayClearPolicy = .onDragOut
        unlockCameraSnapshot = false
    }
}