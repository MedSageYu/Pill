import SwiftUI

/// 4 个页面
enum NotchTab: CaseIterable {
    case home      // 音乐 + 镜子 + 日历
    case files     // AirDrop + 文件托盘
    case clipboard // 剪贴板历史
    case more      // 其他功能

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .files: "folder.fill"
        case .clipboard: "doc.on.clipboard"
        case .more: "ellipsis"
        }
    }

    var label: String {
        switch self {
        case .home: "主页"
        case .files: "文件"
        case .clipboard: "剪贴"
        case .more: "更多"
        }
    }
}