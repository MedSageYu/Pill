import Cocoa
import SwiftUI

/// 灵动岛窗口控制器
/// DragOverlayView 作为窗口 contentView（处理文件拖拽），SwiftUI NSHostingView 作为子视图嵌在其中
final class NotchWindowController: NSObject {
    var window: NotchWindow?
    var vm: NotchViewModel?
    weak var screen: NSScreen?

    override init() {
        super.init()
        setup()
    }

    deinit { destroy() }

    private func setup() {
        logDiag("setup() start, windowHeight=\(NotchViewModel.windowHeight)")
        let allScreens = NSScreen.screens
        logDiag("screens count: \(allScreens.count)")
        for (i, s) in allScreens.enumerated() {
            logDiag("  screen \(i): frame=\(NSStringFromRect(s.frame)) visible=\(NSStringFromRect(s.visibleFrame))")
        }

        // 用鼠标所在的屏幕，不用 NSScreen.main
        let vm = NotchViewModel.shared
        let targetScreen = vm.screenAtMouse() ?? vm.fallbackScreen()
        guard let screen = targetScreen else {
            logDiag("ERROR: no screen!")
            return
        }
        self.screen = screen
        vm.updateScreen(to: screen)
        logDiag("using screen (by mouse): \(NSStringFromRect(screen.frame))")

        positionWindow(on: screen)

        self.vm = vm

        let dragView = DragOverlayView(vm: vm)
        window?.contentView = dragView

        let hostingView = NSHostingView(rootView: NotchView(vm: vm))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        dragView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: dragView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: dragView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: dragView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: dragView.bottomAnchor),
        ])

        window?.makeKeyAndOrderFront(nil)
        logDiag("window frame=\(NSStringFromRect(window?.frame ?? .zero)), isVisible=\(window?.isVisible ?? false)")

        // 屏幕跟随：鼠标移动到其他屏幕时重定位
        vm.onScreenChange = { [weak self] newScreen in
            self?.moveToScreen(newScreen)
        }

        vm.setupEvents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // 全屏状态变化 → 调整窗口
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fullscreenStateChanged),
            name: Notification.Name("NotchStatusDidChange"),
            object: nil
        )
    }

    private func positionWindow(on screen: NSScreen) {
        let wh = NotchViewModel.windowHeight
        let wFrame = CGRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y + screen.frame.height - wh,
            width: screen.frame.width,
            height: wh
        )

        if let existing = window {
            existing.setFrame(wFrame, display: true, animate: true)
        } else {
            let w = NotchWindow(
                contentRect: wFrame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            self.window = w
        }
    }

    private func moveToScreen(_ newScreen: NSScreen) {
        guard newScreen != screen else { return }
        screen = newScreen
        vm?.updateScreen(to: newScreen)
        positionWindow(on: newScreen)
        logDiag("moved to screen: \(NSStringFromRect(newScreen.frame))")
    }

    @objc private func screenDidChange() {
        guard let vm else { return }
        // 仍然用鼠标位置
        let targetScreen = vm.screenAtMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen, targetScreen != screen else { return }
        moveToScreen(targetScreen)
    }

    @objc private func fullscreenStateChanged() {
        // 全屏时降低窗口层级，避免遮挡菜单栏
        if let w = window {
            w.ignoresMouseEvents = (vm?.isFullscreenActive == true && vm?.status == .closed)
        }
    }

    func destroy() {
        vm?.destroy()
        window?.close()
        window = nil
        vm = nil
    }
}

// MARK: - 拖拽处理视图

fileprivate class DragOverlayView: NSView {
    weak var vm: NotchViewModel?

    init(vm: NotchViewModel) {
        self.vm = vm
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, .URL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        vm?.handleDragEntered(at: NSEvent.mouseLocation)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        vm?.handleDragEntered(at: NSEvent.mouseLocation)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        vm?.handleDragExited()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        vm?.handleDrop(urls: urls)
        return true
    }
}

// MARK: - 诊断日志

private func logDiag(_ msg: String) {
    let line = "\(Date().timeIntervalSince1970) [NotchWC] \(msg)\n"
    if let data = line.data(using: .utf8) {
        let path = "/tmp/notch_wc.log"
        if let fh = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            _ = try? fh.seekToEnd()
            _ = try? fh.write(data)
            try? fh.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}
