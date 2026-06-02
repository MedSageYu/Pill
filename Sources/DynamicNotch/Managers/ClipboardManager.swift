import SwiftUI
import AppKit

// MARK: - 剪贴板条目（支持文字 + 图片）

enum ClipboardContent: Equatable {
    case text(String)
    case image(NSImage)

    static func == (lhs: ClipboardContent, rhs: ClipboardContent) -> Bool {
        switch (lhs, rhs) {
        case let (.text(a), .text(b)): return a == b
        case let (.image(a), .image(b)): return a === b
        default: return false
        }
    }
}

struct ClipboardItem: Identifiable, Equatable {
    let id = UUID()
    let content: ClipboardContent
    let timestamp: Date

    var isImage: Bool {
        if case .image = content { return true }
        return false
    }

    var textPreview: String {
        if case let .text(t) = content {
            return t.replacingOccurrences(of: "\n", with: " ").prefix(120).description
        }
        return ""
    }
}

// MARK: - 剪贴板管理器

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published var items: [ClipboardItem] = []

    private let maxItems = 20
    private var changeCount: Int = 0
    private var timer: Timer?

    private init() {
        changeCount = NSPasteboard.general.changeCount
        startPolling()
    }

    deinit { timer?.invalidate() }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPasteboard()
            }
        }
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != changeCount else { return }
        changeCount = pb.changeCount

        // 优先读图片
        if let imgData = pb.data(forType: .tiff), let img = NSImage(data: imgData) {
            // 去重
            if let first = items.first, first.isImage { return }
            let item = ClipboardItem(content: .image(img), timestamp: Date())
            items.insert(item, at: 0)
        }
        // 再读文字
        else if let text = pb.string(forType: .string),
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 去重
            if let first = items.first {
                if case let .text(t) = first.content, t == text { return }
            }
            let item = ClipboardItem(content: .text(text), timestamp: Date())
            items.insert(item, at: 0)
        }

        // 超过 maxItems 自动清理
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
    }

    func copy(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.content {
        case let .text(t): pb.setString(t, forType: .string)
        case let .image(img): pb.writeObjects([img])
        }
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
    }

    func clearAll() { items.removeAll() }
}
