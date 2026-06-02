import SwiftUI

/// 灵动岛主视图
/// 核心设计：收起/展开共用一个连续胶囊形状，无拼接缝隙
struct NotchView: View {
    @ObservedObject var vm: NotchViewModel

    /// pill 视觉高度（收起时的胶囊高度；展开时仅为顶部弧线区）
    private let pillH: CGFloat = 26
    private let radius: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // ── 统一胶囊背景 ──
                unifiedPill(in: geo)

                // ── 折叠态：音乐播放展示（延迟出现，等动画完成）──
                if vm.showCollapsedContent && vm.isMusicPlaying {
                    CollapsedMusicView()
                        .frame(width: vm.effectiveWidth)
                        .zIndex(3)
                }

                // ── 折叠态：通知展示（延迟出现，等动画完成）──
                if vm.showCollapsedContent, let noti = vm.activeNotification {
                    CollapsedNotificationView(notification: noti)
                        .padding(.horizontal, 8)
                        .frame(width: vm.effectiveWidth, height: vm.effectiveHeight)
                        .position(x: geo.size.width / 2, y: vm.effectiveHeight / 2)
                        .zIndex(3)
                }

                // ── 展开内容 ──
                if vm.status == .opened {
                    expandedContent(in: geo)
                        .zIndex(2)
                }
            }
        }
    }

    // MARK: - 统一胶囊

    @ViewBuilder
    private func unifiedPill(in geo: GeometryProxy) -> some View {
        let w = vm.effectiveWidth
        let h = vm.effectiveHeight

        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: radius,
            bottomTrailingRadius: radius, topTrailingRadius: 0
        )
        .fill(Color.black)
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: radius,
                bottomTrailingRadius: radius, topTrailingRadius: 0
            )
            .stroke(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.2), location: 0),
                        .init(color: .white.opacity(0.04), location: 0.3),
                        .init(color: .clear, location: 0.65),
                    ],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 0.5
            )
        )
        .compositingGroup()
        .shadow(
            color: .black.opacity(vm.status == .closed && vm.isHovering ? 0.5 : 0),
            radius: vm.status == .closed && vm.isHovering ? 16 : 0,
            y: vm.status == .closed && vm.isHovering ? 4 : 0
        )
        .animation(.easeInOut(duration: 0.2), value: vm.isHovering)
        .frame(width: w, height: h)
        .position(x: geo.size.width / 2, y: h / 2)
        .animation(vm.animation, value: vm.status)
        .zIndex(1)
    }

    // MARK: - 展开内容

    @ViewBuilder
    private func expandedContent(in geo: GeometryProxy) -> some View {
        let w = vm.notchOpenedSize.width
        let totalH = vm.notchOpenedSize.height
        let contentTopInset: CGFloat = 8

        VStack(spacing: 0) {
            tabBar
            Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
            tabContent
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .padding(.top, contentTopInset)
        .frame(width: w, height: totalH - contentTopInset)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: radius,
                bottomTrailingRadius: radius, topTrailingRadius: 0
            )
        )
        .position(x: geo.size.width / 2, y: (totalH - contentTopInset) / 2)
        .transition(.opacity)
    }

    // MARK: - Tab Bar（左 2 + 右 2，避开刘海）

    private var tabBar: some View {
        HStack(spacing: 0) {
            // 左边：主页、文件
            tabButton(.home)
            tabButton(.files)
            Spacer()
            // 右边：剪贴、更多
            tabButton(.clipboard)
            tabButton(.more)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private func tabButton(_ tab: NotchTab) -> some View {
        let active = vm.activeTab == tab
        return HStack(spacing: 5) {
            Image(systemName: tab.icon).font(.system(size: 11, weight: .medium))
            Text(tab.label).font(.system(size: 11))
        }
        .foregroundColor(active ? .white : .white.opacity(0.45))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(active ? .white.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.18)) {
                vm.activeTab = tab
                vm.showSettings = false
            }
        }
    }

    // MARK: - 内容切换

    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            if vm.showSettings {
                SettingsPanel(vm: vm)
                    .transition(.opacity)
            } else {
                switch vm.activeTab {
                case .home:
                    HomePanelView(vm: vm).transition(.opacity)
                case .files:
                    AirDropFilePanel().transition(.opacity)
                case .clipboard:
                    ClipboardPanelView().transition(.opacity)
                case .more:
                    MorePanelView(vm: vm).transition(.opacity)
                }
            }
        }
    }
}

// MARK: - Home 面板（音乐 | 镜子 | 日历）

private struct HomePanelView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 0) {
            MusicControlView().frame(maxWidth: .infinity, maxHeight: .infinity)
            VLine().opacity(0.08).padding(.vertical, 4)
            MirrorInlinePreview(vm: vm).frame(maxWidth: .infinity)
            VLine().opacity(0.08).padding(.vertical, 4)
            CompactCalendarView(vm: vm).frame(width: 142)
        }
    }
}

// MARK: - AirDrop + 文件托盘 面板（Tab 2）

private struct AirDropFilePanel: View {
    @ObservedObject private var trayMgr = FileTrayManager.shared
    @State private var airDropTarget = false
    @State private var trayTarget = false

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 10) {
                // ── 左 1/3：隔空投送 ──
                airDropZone
                    .frame(width: geo.size.width / 3)

                VLine().opacity(0.06).padding(.vertical, 6)

                // ── 右 2/3：文件托盘 ──
                fileTrayZone
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: $trayTarget) { providers in
                // 统一接收拖放，保存到文件托盘
                providers.saveToTray()
                return true
            }
        }
        .frame(minHeight: 120)
    }

    // ── 隔空投送区域 ──
    private var airDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(airDropTarget ? 0.10 : 0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            .cyan.opacity(airDropTarget ? 0.6 : 0.15),
                            style: StrokeStyle(lineWidth: 1.5, dash: airDropTarget ? [5, 3] : [])
                        )
                }

            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 26))
                    .foregroundStyle(.cyan)
                    .symbolEffect(.pulse, isActive: airDropTarget)

                Text("隔空投送")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .contentShape(Rectangle())
        .onTapGesture { openAirDrop() }
        .onDrop(of: [.fileURL], isTargeted: $airDropTarget) { providers in
            providers.startAirDrop()
            return true
        }
    }

    // ── 文件托盘区域（虚线框）──
    private var fileTrayZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(trayTarget ? 0.06 : 0.02))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            .white.opacity(trayTarget ? 0.4 : 0.15),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                }

            if trayMgr.items.isEmpty {
                // ── 空状态：提示文字 ──
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("把文件拖在此")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }
            } else {
                // ── 有文件：网格展示 ──
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(trayMgr.items) { item in
                            FileItemView(item: item)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 110)
    }

    private func openAirDrop() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            let service = NSSharingService(named: .sendViaAirDrop)
            guard let service, service.canPerform(withItems: panel.urls) else {
                let alert = NSAlert()
                alert.messageText = "隔空投送不可用，请检查设置。"
                alert.alertStyle = .informational
                alert.runModal()
                return
            }
            service.perform(withItems: panel.urls)
        }
    }
}

// MARK: - 文件托盘单项视图（支持拖出）

private struct FileItemView: View {
    let item: TrayFileItem
    @ObservedObject private var mgr = FileTrayManager.shared
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)

            Text(item.name)
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 72)

            Text(formattedDate)
                .font(.system(size: 7))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(6)
        .frame(width: 80)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? .white.opacity(0.1) : .white.opacity(0.04))
        )
        .onHover { isHovering = $0 }
        .onTapGesture { mgr.open(item) }
        .onDrag {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                mgr.handleDragOut(item)
            }
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
    }

    private var formattedDate: String {
        let df = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(item.addedAt) {
            df.dateFormat = "HH:mm"
        } else if cal.isDateInYesterday(item.addedAt) {
            return "昨天"
        } else {
            df.dateFormat = "MM/dd"
        }
        return df.string(from: item.addedAt)
    }
}

// MARK: - More 面板（功能网格）

private struct MorePanelView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 4), spacing: 10) {
            ToolButton(icon: "gearshape.fill", label: "设置", color: .gray) {
                withAnimation(.easeOut(duration: 0.18)) { vm.activeTab = .more }
                vm.showSettings = true
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - 工具按钮

private struct ToolButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }
}

// MARK: - 垂直分割线

private struct VLine: View {
    var body: some View {
        Rectangle().fill(.white).frame(width: 0.5)
    }
}

// MARK: - View 条件修饰符扩展

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - 折叠态音乐展示

private struct CollapsedMusicView: View {
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let art = music.artworkImage {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5))
                } else if let icon = music.currentAppIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                        .opacity(0.7)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(width: 18, height: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
            .padding(.leading, 12)
            .offset(y: 1)

            Spacer()

            WaveformView(isPlaying: music.isPlaying)
                .frame(width: 50, height: 16)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 折叠态通知展示

private struct CollapsedNotificationView: View {
    let notification: IncomingNotification
    @ObservedObject private var vm = NotchViewModel.shared

    var body: some View {
        HStack(spacing: 5) {
            Text(String(notification.appName.prefix(1)))
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Color.blue.opacity(0.6)))

            VStack(alignment: .leading, spacing: 0) {
                Text(notification.title)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !notification.subtitle.isEmpty {
                    Text(notification.subtitle)
                        .font(.system(size: 6))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
    }
}