import SwiftUI

/// 3 个页面（.more 保留但不在 Tab 栏显示，未来扩展用）
enum NotchTab: CaseIterable {
    case home      // 音乐 + 镜子 + 日历
    case files     // AirDrop + 文件托盘
    case clipboard // 剪贴板历史
    // case more  // 保留给未来功能，当前不显示

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .files: "folder.fill"
        case .clipboard: "doc.on.clipboard"
        }
    }

    var label: String {
        switch self {
        case .home: "主页"
        case .files: "文件"
        case .clipboard: "剪贴"
        }
    }
}
