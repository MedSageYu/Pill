import AVFoundation
import Cocoa
import SwiftUI
import EventKit

// MARK: - CameraPreviewView（自定 NSView，自动同步 previewLayer）

fileprivate class CameraPreviewView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet { oldValue?.removeFromSuperlayer() }
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
        // 动态圆角：始终保持正圆
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        previewLayer?.frame = bounds
    }
}

// MARK: - CameraView (NSViewRepresentable)

fileprivate struct CameraView: NSViewRepresentable {
    let isActive: Bool
    let isMirrored: Bool

    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.masksToBounds = true
        // cornerRadius 由 layout() 动态计算
        return view
    }

    func updateNSView(_ view: CameraPreviewView, context: Context) {
        if isActive {
            context.coordinator.ensureSession(in: view)
        } else {
            context.coordinator.stopSession(in: view)
        }
        context.coordinator.setMirror(isMirrored)
        view.needsLayout = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var session: AVCaptureSession?
        private weak var currentView: CameraPreviewView?

        func ensureSession(in view: CameraPreviewView) {
            if session != nil, currentView === view { return }

            // SwiftUI 重建 view 时重建 session
            if session != nil {
                stopSession(in: currentView ?? view)
            }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                      for: .video,
                                                      position: .front)
                  ?? AVCaptureDevice.default(for: .video) else {
                print("[Camera] 无可用摄像头")
                return
            }

            do {
                let s = AVCaptureSession()
                s.sessionPreset = .medium
                let input = try AVCaptureDeviceInput(device: device)
                guard s.canAddInput(input) else { return }
                s.addInput(input)

                let layer = AVCaptureVideoPreviewLayer(session: s)
                layer.videoGravity = .resizeAspectFill
                layer.frame = view.bounds
                view.layer?.addSublayer(layer)
                view.previewLayer = layer
                currentView = view

                session = s
                s.startRunning()
                print("[Camera] OK bound=\(view.bounds)")
            } catch {
                print("[Camera] 启动失败: \(error)")
            }
        }

        func stopSession(in view: CameraPreviewView) {
            session?.stopRunning()
            view.previewLayer?.removeFromSuperlayer()
            view.previewLayer = nil
            session = nil
            currentView = nil
        }

        func setMirror(_ mirrored: Bool) {
            guard let layer = currentView?.previewLayer else { return }
            layer.setAffineTransform(CGAffineTransform(scaleX: mirrored ? -1 : 1, y: 1))
        }
    }
}

// MARK: - 镜子内联预览（主页中间直接显示）

struct MirrorInlinePreview: View {
    @ObservedObject var vm: NotchViewModel
    @State private var isActive = false
    @State private var permissionDenied = false

    var body: some View {
        Group {
            if permissionDenied {
                VStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                    Text("无权限")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            } else if isActive {
                CameraView(isActive: isActive, isMirrored: vm.mirrorEnabled)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(4)
            } else {
                Button { requestAndStart() } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.06))
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(width: 80, height: 80)
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            isActive = false
        }
    }

    private func requestAndStart() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isActive = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { isActive = true } else { permissionDenied = true }
                }
            }
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
    }
}

// MARK: - 设置面板（更多页）

struct SettingsPanel: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var calendarStore = CalendarStore.shared
    @StateObject private var updateChecker = UpdateChecker.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // 返回按钮
                HStack {
                    Button {
                        vm.showSettings = false
                        vm.activeTab = .home
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                            Text("返回").font(.system(size: 10))
                        }
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                Text("设置").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).padding(.top, 6)

                Divider().background(.white.opacity(0.08)).padding(.vertical, 6)

                // ── 自动收起时间 ──
                HStack(spacing: 6) {
                    Image(systemName: "timer").font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 14)
                    Text("自动收起").font(.system(size: 10)).foregroundStyle(.white)
                    Spacer()
                    Text(String(format: "%.1fs", vm.autoCloseSeconds))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 36, alignment: .trailing)
                    Slider(value: $vm.autoCloseSeconds, in: 0.5...10.0)
                        .frame(width: 64)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)

                Divider().background(.white.opacity(0.06)).padding(.horizontal, 8)

                // ── 收起时高度 ──
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.and.down").font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 14)
                    Text("收起高度").font(.system(size: 10)).foregroundStyle(.white)
                    Spacer()
                    Text("\(Int(vm.collapsedHeight))pt")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, alignment: .trailing)
                    Slider(value: Binding(get: { vm.collapsedHeight }, set: { vm.setCustomCollapsedHeight($0) }), in: 18...40)
                        .frame(width: 64)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)

                Divider().background(.white.opacity(0.06)).padding(.horizontal, 8)

                // ── 镜像翻转 ──
                settingRow(
                    icon: "arrow.left.arrow.right",
                    title: "镜像翻转",
                    detail: vm.mirrorEnabled ? "开" : "关",
                    control: {
                        Toggle("", isOn: $vm.mirrorEnabled).toggleStyle(.switch).scaleEffect(0.7)
                    }
                )

                // ── 日历选择（固定高度，内部滚动）──
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.plus").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                        Text("日历显示").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    }
                        .padding(.top, 8).padding(.horizontal, 8)
                    Text("勾选要在主页展示的日历")
                        .font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 8).padding(.bottom, 2)

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(calendarStore.allCalendars, id: \.calendarIdentifier) { cal in
                                calendarRow(cal)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .frame(maxHeight: 100)
                }

                Divider().background(.white.opacity(0.06)).padding(.horizontal, 8)

                // ── 文件托盘设置 ──
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                        Text("文件托盘设置").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    }
                        .padding(.top, 8).padding(.horizontal, 8)
                    Text("文件拖入托盘后的自动清除规则")
                        .font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 8).padding(.bottom, 4)
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 14)
                        Text("自动清除策略").font(.system(size: 10)).foregroundStyle(.white)
                        Spacer()
                        Menu {
                            ForEach(FileTrayClearPolicy.allCases) { policy in
                                Button {
                                    settings.fileTrayClearPolicy = policy
                                } label: {
                                    HStack {
                                        Text(policy.label)
                                        if settings.fileTrayClearPolicy == policy {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(settings.fileTrayClearPolicy.label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.7))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.08)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                }

                Divider().background(.white.opacity(0.06)).padding(.horizontal, 8)

                // ── 检查更新 ──
                updateSection

                Divider().background(.white.opacity(0.06)).padding(.horizontal, 8)

                // ── 退出 ──
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "power")
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.8))
                        Text("退出 Pill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.8))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer().frame(height: 8)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4).padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func settingRow<C: View>(
        icon: String, title: String, detail: String,
        @ViewBuilder control: () -> C
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 14)
            Text(title).font(.system(size: 10)).foregroundStyle(.white)
            Spacer()
            Text(detail)
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            control()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func calendarRow(_ cal: EKCalendar) -> some View {
        let isOn = Binding<Bool>(
            get: { vm.selectedCalendarIDs.isEmpty || vm.selectedCalendarIDs.contains(cal.calendarIdentifier) },
            set: { checked in
                if vm.selectedCalendarIDs.isEmpty {
                    vm.selectedCalendarIDs = Set(calendarStore.allCalendars.map(\.calendarIdentifier))
                }
                if checked { vm.selectedCalendarIDs.insert(cal.calendarIdentifier) }
                else { vm.selectedCalendarIDs.remove(cal.calendarIdentifier) }
            }
        )
        return HStack(spacing: 5) {
            Circle().fill(Color(cal.color)).frame(width: 6, height: 6)
            Text(cal.title).font(.system(size: 9)).foregroundColor(.white.opacity(0.65)).lineLimit(1)
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.checkbox).scaleEffect(0.65)
        }
        .padding(.horizontal, 8).padding(.vertical, 2)
    }

    // MARK: - 检查更新

    @ViewBuilder
    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                Text("版本更新").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            }
                .padding(.top, 8).padding(.horizontal, 8)

            switch updateChecker.status {
            case .idle:
                Button {
                    updateChecker.check()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 10))
                        Text("检查更新").font(.system(size: 10))
                        Text("v\(updateChecker.currentVersion)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 2)

            case .checking:
                HStack(spacing: 5) {
                    ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                    Text("正在检查...").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)

            case .upToDate:
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green)
                    Text("已是最新")
                        .font(.system(size: 10)).foregroundStyle(.green.opacity(0.8))
                    Text("v\(updateChecker.currentVersion)")
                        .font(.system(size: 8, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { updateChecker.status = .idle }

            case let .updateAvailable(_, latest, url):
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                        Text("发现新版本 v\(latest)")
                            .font(.system(size: 10)).foregroundStyle(.orange)
                    }
                    if let url {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill").font(.system(size: 10))
                                Text("前往下载")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5).fill(.orange.opacity(0.3))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)

            case let .error(msg):
                HStack(spacing: 5) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.red.opacity(0.7))
                    Text(msg).font(.system(size: 9)).foregroundStyle(.red.opacity(0.7))
                    Button("重试") { updateChecker.check() }
                        .font(.system(size: 8)).foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.08)))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
        }
    }
}