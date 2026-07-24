import Cocoa
import SwiftUI

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// 镜子二级页面状态
enum MirrorSubPage {
    case main       // 一级：镜子实时预览
    case snapshots  // 二级：解锁拍照记录
}

/// 灵动岛视图状态管理
/// 核心交互逻辑：全局事件监听捕获鼠标位置和点击 → 坐标判断决定开/关
final class NotchViewModel: NSObject, ObservableObject {
    static let shared = NotchViewModel()

    enum Status: Equatable {
        case closed
        case opened
    }

    override init() {
        let ud = UserDefaults.standard
        if ud.object(forKey: "collapsedHeight") != nil {
            let h = CGFloat(ud.double(forKey: "collapsedHeight"))
            collapsedHeight = h
            notchClosedSize.height = h
            hasCustomizedHeight = true
        }
        if ud.object(forKey: "autoCloseSeconds") != nil {
            autoCloseSeconds = ud.double(forKey: "autoCloseSeconds")
        }
        if ud.object(forKey: "mirrorEnabled") != nil {
            mirrorEnabled = ud.bool(forKey: "mirrorEnabled")
        }
        if let ids = ud.object(forKey: "selectedCalendarIDs") as? [String] {
            selectedCalendarIDs = Set(ids)
        }

        // 启动时清理过期缓存
        DispatchQueue.global(qos: .background).async {
            Self.cleanupStaleCaches()
        }

        super.init()

        // 全屏检测
        setupFullscreenDetection()
    }

    // MARK: - 尺寸

    let spacing: CGFloat = 16
    let cornerRadius: CGFloat = 22
    let inset: CGFloat = -4

    private var hasCustomizedHeight = false

    @Published var collapsedHeight: CGFloat = 26 {
        didSet {
            guard hasCustomizedHeight else { return }
            notchClosedSize.height = collapsedHeight
            UserDefaults.standard.set(collapsedHeight, forKey: "collapsedHeight")
        }
    }
    var notchClosedSize: CGSize = .init(width: 165, height: 26)
    var notchOpenedSize: CGSize = .init(width: 480, height: 190)

    func recomputeAdaptiveSizes(for screen: NSScreen? = nil) {
        let sr = screen?.frame ?? screenRect
        guard sr.width > 0, sr.height > 0 else { return }

        let sw = sr.width
        let sh = sr.height
        let menuBarH = sh - (screen?.visibleFrame.height ?? sh)
        let hasNotch = menuBarH >= 30

        let closedW = (sw * 0.13).clamped(to: 155...220)
        let defaultClosedH: CGFloat = hasNotch ? 26 : 22

        let expandedW = (sw * 0.35).clamped(to: 420...580)
        let expandedH = (sh * 0.21).clamped(to: 170...230)

        notchClosedSize.width = closedW
        notchOpenedSize = CGSize(width: expandedW, height: expandedH)

        if !hasCustomizedHeight {
            collapsedHeight = defaultClosedH
            notchClosedSize.height = defaultClosedH
        }
    }

    static var windowHeight: CGFloat { shared.notchOpenedSize.height + 20 }

    var effectiveHeight: CGFloat {
        switch status {
        case .closed: notchClosedSize.height
        case .opened: notchOpenedSize.height
        }
    }

    var effectiveWidth: CGFloat {
        if status == .opened { return notchOpenedSize.width }
        if isMusicPlaying || activeNotification != nil { return 200 }
        return notchClosedSize.width
    }

    @Published var isMusicPlaying: Bool = false
    @Published var activeNotification: IncomingNotification?

    // MARK: - 发布状态

    @Published var status: Status = .closed {
        didSet {
            NotificationCenter.default.post(
                name: NSNotification.Name("NotchStatusDidChange"), object: nil)
        }
    }
    @Published var showCollapsedContent = true
    @Published var isHovering = false
    @Published var screenRect: CGRect = .zero
    @Published var activeTab: NotchTab = .home
    @Published var showSettings: Bool = false
    @Published var mirrorSubPage: MirrorSubPage = .main
    @Published var mirrorEnabled: Bool = true {
        didSet { UserDefaults.standard.set(mirrorEnabled, forKey: "mirrorEnabled") }
    }
    @Published var autoCloseSeconds: Double = 2.0 {
        didSet { UserDefaults.standard.set(autoCloseSeconds, forKey: "autoCloseSeconds") }
    }
    @Published var selectedCalendarIDs: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(selectedCalendarIDs), forKey: "selectedCalendarIDs")
        }
    }

    // MARK: - 全屏状态

    /// 当前屏幕是否有全屏应用（如视频播放器）
    @Published var isFullscreenActive = false
    /// 当前鼠标所在的屏幕（用于多屏跟随）
    var currentScreen: NSScreen?
    private var fullscreenCheckTimer: Timer?
    private var spaceChangeObserver: NSObjectProtocol?

    private func setupFullscreenDetection() {
        // 每 1.5 秒轮询全屏窗口（开销极低，仅 CGWindowList）
        fullscreenCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkFullscreenState()
        }
        // Space 切换时立即检查
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkFullscreenState()
        }
    }

    private func checkFullscreenState() {
        let wasFullscreen = isFullscreenActive
        // 检查所有屏幕（单窗口 + canJoinAllSpaces 使 pill 出现在每个屏幕）
        isFullscreenActive = NSScreen.screens.contains { screen in
            detectFullscreenWindow(on: screen.frame)
        }

        // 刚进入全屏 → 自动收起
        if isFullscreenActive, !wasFullscreen, status == .opened {
            DispatchQueue.main.async { [weak self] in
                self?.closeNotch()
            }
        }
    }

    /// 检测目标屏幕上是否有全屏应用窗口
    private func detectFullscreenWindow(on screenFrame: CGRect) -> Bool {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else { return false }

        for window in windowList {
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let name = window[kCGWindowOwnerName as String] as? String,
                  name != "Pill",
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }

            let x = bounds["X"] ?? 0, y = bounds["Y"] ?? 0
            let w = bounds["Width"] ?? 0, h = bounds["Height"] ?? 0

            // 窗口覆盖整屏（允许 ±2px 误差）
            if abs(x - screenFrame.origin.x) < 3,
               abs(y - screenFrame.origin.y) < 3,
               abs(w - screenFrame.width) < 3,
               abs(h - screenFrame.height) < 3 {
                return true
            }
        }
        return false
    }

    // MARK: - 屏幕跟随（多屏环境）

    /// 根据鼠标位置确定当前屏幕
    func screenAtMouse() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(loc) }
    }

    func fallbackScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    /// NotchWindowController 检测到屏幕切换时调用，更新 screenRect 并重定位
    func updateScreen(to screen: NSScreen) {
        currentScreen = screen
        screenRect = screen.frame
        recomputeAdaptiveSizes(for: screen)
    }

    // MARK: - 全局事件监听器

    private var mouseMoveMonitor: EventMonitor?
    private var mouseDownMonitor: EventMonitor?
    private var rightMouseDownMonitor: EventMonitor?
    private var wasInsideOpened = false

    /// 外部回调：屏幕变化时 NotchWindowController 调用
    var onScreenChange: ((NSScreen) -> Void)?

    func setupEvents() {
        // 全局鼠标移动
        mouseMoveMonitor = EventMonitor(mask: .mouseMoved) { [weak self] _ in
            guard let self else { return }
            let loc = NSEvent.mouseLocation

            // 屏幕跟随：检测鼠标是否移动到其他屏幕
            if let newScreen = self.screenAtMouse(), newScreen != self.currentScreen {
                self.onScreenChange?(newScreen)
            }

            let nearCollapsed = self.hitRect.contains(loc)
            let insideOpened = self.status == .opened && self.hitRectOpened.contains(loc)

            DispatchQueue.main.async {
                self.isHovering = nearCollapsed

                if !insideOpened, self.wasInsideOpened {
                    self.startAutoClose()
                } else if insideOpened {
                    self.cancelAutoClose()
                }
                self.wasInsideOpened = insideOpened
            }
        }
        mouseMoveMonitor?.start()

        // 全局鼠标按下
        mouseDownMonitor = EventMonitor(mask: .leftMouseDown) { [weak self] _ in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            DispatchQueue.main.async {
                switch self.status {
                case .opened:
                    if !self.hitRectOpened.contains(loc) {
                        self.closeNotch()
                    }
                case .closed:
                    if self.hitRect.contains(loc) {
                        self.openNotch()
                    }
                }
            }
        }
        mouseDownMonitor?.start()

        // 右键退出菜单
        rightMouseDownMonitor = EventMonitor(mask: .rightMouseDown) { [weak self] _ in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            if self.status == .closed, self.hitRect.contains(loc) {
                DispatchQueue.main.async { self.showQuitMenu() }
            }
        }
        rightMouseDownMonitor?.start()
    }

    func destroy() {
        mouseMoveMonitor?.stop()
        mouseDownMonitor?.stop()
        rightMouseDownMonitor?.stop()
        fullscreenCheckTimer?.invalidate()
        fullscreenCheckTimer = nil
        if let obs = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            spaceChangeObserver = nil
        }
    }

    // MARK: - 命中区域

    /// 折叠态命中区
    /// 全屏时：仅屏幕顶部 6px 触发条（防止误触视频控制栏）
    var hitRect: CGRect {
        if isFullscreenActive, status == .closed {
            // 全屏隐藏态：仅顶部 6px 窄条触发
            let sr = screenRect
            return CGRect(
                x: sr.origin.x + (sr.width - 300) / 2,
                y: sr.maxY - 6,
                width: 300,
                height: 6
            )
        }
        let w = effectiveWidth, h = notchClosedSize.height
        let x = screenRect.origin.x + (screenRect.width - w) / 2
        let y = screenRect.origin.y + screenRect.height - h
        return CGRect(x: x, y: y, width: w, height: h)
            .insetBy(dx: inset, dy: inset)
    }

    var hitRectOpened: CGRect {
        let w = notchOpenedSize.width, h = notchOpenedSize.height
        let x = screenRect.origin.x + (screenRect.width - w) / 2
        let y = screenRect.origin.y + screenRect.height - h
        return CGRect(x: x, y: y, width: w, height: h)
            .insetBy(dx: inset, dy: inset)
    }

    func setCustomCollapsedHeight(_ h: CGFloat) {
        hasCustomizedHeight = true
        collapsedHeight = h
        notchClosedSize.height = h
        UserDefaults.standard.set(h, forKey: "collapsedHeight")
    }

    let animation: Animation = .interactiveSpring(
        duration: 0.5, extraBounce: 0.2, blendDuration: 0.125)

    var tabTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)),
            removal: .opacity)
    }

    // MARK: - 坐标计算

    var notchRect: CGRect {
        CGRect(
            x: screenRect.origin.x + (screenRect.width - effectiveWidth) / 2,
            y: screenRect.origin.y + screenRect.height - effectiveHeight,
            width: effectiveWidth,
            height: effectiveHeight)
    }

    var notchRectInWindow: CGRect {
        let w = effectiveWidth, h = effectiveHeight
        if status == .opened {
            return CGRect(x: 0, y: 0, width: screenRect.width, height: Self.windowHeight)
        }
        return CGRect(x: (screenRect.width - w) / 2, y: Self.windowHeight - h,
                      width: w, height: h)
    }

    // MARK: - 状态变换

    func openNotch() {
        showCollapsedContent = false
        // 每次展开自动回到镜子一级页面
        mirrorSubPage = .main
        withAnimation(animation) { status = .opened }
        cancelAutoClose()
    }

    func closeNotch() {
        showCollapsedContent = false
        withAnimation(animation) { status = .closed }
        cancelAutoClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.showCollapsedContent = true
        }
    }

    // MARK: - 自动收起

    private var autoCloseTimer: Timer?

    func startAutoClose() {
        cancelAutoClose()
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: autoCloseSeconds, repeats: false) { [weak self] _ in
            self?.closeNotch()
        }
    }

    func cancelAutoClose() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
    }

    // MARK: - 右键退出菜单

    private func showQuitMenu() {
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "退出 Pill",
            action: #selector(quitApplication),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        let point = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - 通知

    func receiveNotification(_ noti: IncomingNotification) {
        activeNotification = noti
        if status == .closed { openNotch() }
        cancelAutoClose()
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                self?.activeNotification = nil
            }
            self?.closeNotch()
        }
    }

    func dismissNotification() {
        withAnimation(.easeInOut(duration: 0.3)) {
            activeNotification = nil
        }
    }

    func openNotificationApp() {
        guard let noti = activeNotification else { return }
        NotificationManager.openApp(bundleID: noti.appBundleID)
        dismissNotification()
        closeNotch()
    }

    // MARK: - 隔空投送

    @Published var isDragTargetActive: Bool = false
    @Published var pendingAirDropFile: AirDropFile?
    private var airDropService: NSSharingService?

    func handleDragEntered(at screenLoc: NSPoint) {
        let trigger = hitRect.insetBy(dx: -200, dy: -200)
        guard trigger.contains(screenLoc) else { return }
        if status != .opened { openNotch() }
        isDragTargetActive = true
    }

    func handleDragExited() {
        isDragTargetActive = false
    }

    func handleDrop(urls: [URL]) {
        guard let url = urls.first else { return }
        isDragTargetActive = false

        cleanupAirDropFile()

        let cacheDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/Pill/AirDrop")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let dest = cacheDir.appendingPathComponent(url.lastPathComponent)
        let destURL = dest.uniqueName()
        try? FileManager.default.copyItem(at: url, to: destURL)

        let typeName = destURL.pathExtension.isEmpty ? "文件" : destURL.pathExtension.uppercased()
        let icon = NSWorkspace.shared.icon(forFile: destURL.path)
        let file = AirDropFile(
            name: url.lastPathComponent,
            type: typeName,
            icon: icon,
            localURL: destURL
        )
        pendingAirDropFile = file
        presentAirDrop(with: [destURL])
    }

    private func presentAirDrop(with urls: [URL]) {
        let service = NSSharingService(named: .sendViaAirDrop)
        guard let service, service.canPerform(withItems: urls) else {
            DispatchQueue.main.async { [weak self] in
                self?.cleanupAirDropFile()
                let alert = NSAlert()
                alert.messageText = "隔空投送不可用"
                alert.informativeText = "请检查 Wi-Fi 是否开启。"
                alert.runModal()
            }
            return
        }
        airDropService = service
        service.delegate = self
        service.perform(withItems: urls)
    }

    private func cleanupAirDropFile() {
        if let prev = pendingAirDropFile {
            try? FileManager.default.removeItem(at: prev.localURL)
        }
        pendingAirDropFile = nil
        airDropService = nil
    }

    func dismissAirDropFile() {
        cleanupAirDropFile()
    }

    // MARK: - 缓存清理

    static func cleanupStaleCaches() {
        let fm = FileManager.default
        let home = NSHomeDirectory()

        let airdropDir = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Caches/Pill/AirDrop")
        if let files = try? fm.contentsOfDirectory(at: airdropDir,
            includingPropertiesForKeys: nil) {
            for f in files { try? fm.removeItem(at: f) }
        }

        let trayDir = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Caches/Pill/TrayDrop")
        if let files = try? fm.contentsOfDirectory(at: trayDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) {
            let sorted = files.sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return da > db
            }
            for f in sorted.dropFirst(20) {
                try? fm.removeItem(at: f)
            }
        }

        let logPath = "/tmp/notch_wc.log"
        if fm.fileExists(atPath: logPath),
           let attrs = try? fm.attributesOfItem(atPath: logPath),
           let size = attrs[.size] as? Int, size > 512_000 {
            if let fh = FileHandle(forUpdatingAtPath: logPath) {
                defer { try? fh.close() }
                let keepSize = 512_000
                let seekOffset = UInt64(size - keepSize)
                if #available(macOS 10.15.4, *) {
                    try? fh.seek(toOffset: seekOffset)
                } else {
                    fh.seek(toFileOffset: seekOffset)
                }
                let tail = fh.readDataToEndOfFile()
                try? fh.truncate(atOffset: 0)
                let marker = "[truncated]\n".data(using: .utf8)!
                try? fh.write(contentsOf: marker + tail)
            }
        }
    }
}

struct AirDropFile {
    let name: String
    let type: String
    let icon: NSImage
    let localURL: URL
}

extension NotchViewModel: NSSharingServiceDelegate {
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        cleanupAirDropFile()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        cleanupAirDropFile()
    }
}

struct IncomingNotification: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let appBundleID: String
    let appName: String
    let timestamp: Date
    var delivered: Bool = false

    static func == (lhs: IncomingNotification, rhs: IncomingNotification) -> Bool {
        lhs.id == rhs.id
    }
}
