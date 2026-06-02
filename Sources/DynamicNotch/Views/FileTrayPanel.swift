import Cocoa
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 文件托盘项（带时间戳）

struct TrayFileItem: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let addedAt: Date

    /// 存储路径（运行时计算，不持久化）
    var url: URL {
        FileTrayManager.storageDir.appendingPathComponent(name)
    }

    /// Finder 图标（运行时获取）
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    static func == (lhs: TrayFileItem, rhs: TrayFileItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 文件托盘管理器

final class FileTrayManager: ObservableObject {
    static let shared = FileTrayManager()

    static let storageDir: URL = {
        let d = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Pill/FileTray")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static let itemsFile: URL = {
        storageDir.appendingPathComponent("tray_items.json")
    }()

    @Published var items: [TrayFileItem] = []
    private var autoClearTimer: Timer?

    /// 文件托盘最大保留数量，超过自动删最旧的
    private let maxItems = 50

    private init() {
        loadItems()
        scheduleAutoClear()
    }

    // MARK: - 持久化

    private func loadItems() {
        guard let data = try? Data(contentsOf: Self.itemsFile),
              let saved = try? JSONDecoder().decode([TrayFileItem].self, from: data)
        else { return }

        // 只保留文件仍然存在的项
        items = saved.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        trimIfNeeded()
        saveItems()
    }

    private func saveItems() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: Self.itemsFile, options: .atomic)
    }

    // MARK: - 文件操作

    /// 拖入文件 → 复制到托盘（原位不动）
    func add(_ url: URL) {
        let dest = Self.storageDir.appendingPathComponent(url.lastPathComponent).uniqueName()
        guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return }
        let item = TrayFileItem(
            id: UUID(),
            name: dest.lastPathComponent,
            addedAt: Date()
        )
        items.insert(item, at: 0)
        trimIfNeeded()
        saveItems()
    }

    /// 超出上限时删除最旧的条目（含磁盘文件）
    private func trimIfNeeded() {
        guard items.count > maxItems else { return }
        let toRemove = items.suffix(items.count - maxItems)
        for item in toRemove {
            try? FileManager.default.removeItem(at: item.url)
        }
        items = Array(items.prefix(maxItems))
    }

    /// 从托盘拖出 → 根据策略决定是否清除
    func handleDragOut(_ item: TrayFileItem) {
        switch AppSettings.shared.fileTrayClearPolicy {
        case .onDragOut:
            remove(item)
        case .never, .after1Hour, .after2Hours, .after1Day:
            break // 保留，由自动清除定时器处理
        }
    }

    /// 手动删除
    func remove(_ item: TrayFileItem) {
        try? FileManager.default.removeItem(at: item.url)
        items.removeAll { $0.id == item.id }
        saveItems()
    }

    /// 打开文件
    func open(_ item: TrayFileItem) {
        NSWorkspace.shared.open(item.url)
    }

    /// 在 Finder 中显示
    func reveal(_ item: TrayFileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: - 自动清除

    private func scheduleAutoClear() {
        autoClearTimer?.invalidate()
        // 每分钟检查一次
        autoClearTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkAutoClear()
        }
    }

    private func checkAutoClear() {
        let policy = AppSettings.shared.fileTrayClearPolicy
        guard let interval = policy.interval else { return }

        let now = Date()
        let expired = items.filter { now.timeIntervalSince($0.addedAt) >= interval }
        for item in expired {
            try? FileManager.default.removeItem(at: item.url)
        }
        items.removeAll { now.timeIntervalSince($0.addedAt) >= interval }
        if !expired.isEmpty {
            trimIfNeeded()
            saveItems()
        }
    }
}

// MARK: - NSItemProvider 扩展

extension [NSItemProvider] {
    /// 拖入文件到文件托盘
    func saveToTray() {
        DispatchQueue.global().async {
            var urls: [URL] = []
            let group = DispatchGroup()

            for provider in self {
                group.enter()
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                        if let url = item as? URL {
                            urls.append(url)
                        } else if let data = item as? Data,
                                  let u = URL(dataRepresentation: data, relativeTo: nil) {
                            urls.append(u)
                        }
                        group.leave()
                    }
                } else {
                    group.leave()
                }
            }
            group.wait()

            for url in urls {
                DispatchQueue.main.async {
                    FileTrayManager.shared.add(url)
                }
            }
        }
    }
}

// MARK: - URL 去重

extension URL {
    func uniqueName() -> URL {
        var u = self
        let stem = deletingPathExtension().lastPathComponent
        let ext = pathExtension.isEmpty ? "" : ".\(pathExtension)"
        var n = 1
        while FileManager.default.fileExists(atPath: u.path) {
            u = deletingLastPathComponent()
                .appendingPathComponent("\(stem)-\(n)\(ext)")
            n += 1
        }
        return u
    }
}