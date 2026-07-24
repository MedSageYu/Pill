import AVFoundation
import Cocoa
import SwiftUI
import Combine

// MARK: - 解锁拍照记录

struct UnlockSnapshot: Identifiable {
    let id = UUID()
    let image: NSImage
    let timestamp: Date
}

/// 监听屏幕解锁事件，用前置摄像头拍照保存最近 4 张
@MainActor
final class UnlockCameraManager: ObservableObject {
    static let shared = UnlockCameraManager()

    @Published var snapshots: [UnlockSnapshot] = []

    private let maxSnapshots = 4
    private var session: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var isCapturing = false
    private var unlockObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    private init() {
        guard AppSettings.shared.unlockCameraSnapshot else { return }
        startMonitoring()
    }

    func startMonitoring() {
        guard unlockObserver == nil else { return }

        // 屏幕解锁通知
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.captureSnapshot()
            }
        }

        // 屏幕唤醒（从睡眠恢复）
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // 唤醒后延迟 2 秒，等摄像头就绪
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.captureSnapshot()
            }
        }
    }

    func stopMonitoring() {
        if let obs = unlockObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            unlockObserver = nil
        }
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            wakeObserver = nil
        }
        stopSession()
    }

    // MARK: - 摄像头拍照

    private func captureSnapshot() {
        guard AppSettings.shared.unlockCameraSnapshot else { return }
        guard !isCapturing else { return }

        isCapturing = true

        // 确保摄像头权限
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            performCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted { self?.performCapture() }
                    else { self?.isCapturing = false }
                }
            }
        case .denied, .restricted:
            isCapturing = false
        @unknown default:
            isCapturing = false
        }
    }

    private func performCapture() {
        // 创建临时 session 拍照
        Task { @MainActor in
            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                        ?? AVCaptureDevice.default(for: .video) else {
                    isCapturing = false
                    return
                }

                let session = AVCaptureSession()
                session.sessionPreset = .medium

                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    isCapturing = false
                    return
                }
                session.addInput(input)

                let output = AVCapturePhotoOutput()
                guard session.canAddOutput(output) else {
                    isCapturing = false
                    return
                }
                session.addOutput(output)

                self.session = session
                self.photoOutput = output

                session.startRunning()

                // 等 session 稳定
                try? await Task.sleep(nanoseconds: 500_000_000)

                let settings = AVCapturePhotoSettings()
                settings.isHighResolutionPhotoEnabled = false

                let delegate = PhotoCaptureDelegate { [weak self] image in
                    Task { @MainActor in
                        guard let self else { return }
                        if let image {
                            self.addSnapshot(image)
                        }
                        self.stopSession()
                        self.isCapturing = false
                    }
                }
                // delegate 需要保持引用
                objc_setAssociatedObject(self, &Self.delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
                output.capturePhoto(with: settings, delegate: delegate)
            } catch {
                isCapturing = false
            }
        }
    }

    private func stopSession() {
        session?.stopRunning()
        session = nil
        photoOutput = nil
    }

    private func addSnapshot(_ image: NSImage) {
        // 镜像翻转（前置摄像头自然镜像）
        let mirrored = mirrorImage(image)

        let snapshot = UnlockSnapshot(image: mirrored, timestamp: Date())
        snapshots.insert(snapshot, at: 0)
        if snapshots.count > maxSnapshots {
            snapshots = Array(snapshots.prefix(maxSnapshots))
        }
        print("[UnlockCamera] 拍照成功，共 \(snapshots.count) 张")
    }

    private func mirrorImage(_ image: NSImage) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let flipped = NSImage(size: image.size)
        flipped.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: image.size.width, y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(cgImage, in: NSRect(origin: .zero, size: image.size))
        flipped.unlockFocus()
        return flipped
    }

    private static var delegateKey: UInt8 = 0
}

// MARK: - 拍照委托

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (NSImage?) -> Void

    init(completion: @escaping (NSImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: (any Error)?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = NSImage(data: data) else {
            completion(nil)
            return
        }
        completion(image)
    }
}
