import Foundation

/// GitHub 更新检查模型
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate(current: String)
        case updateAvailable(current: String, latest: String, url: URL?)
        case error(String)
    }

    @Published var status: Status = .idle

    private let repoOwner = "MedSageYu"
    private let repoName = "Pill"
    private let session = URLSession(configuration: .ephemeral)

    /// 当前版本（从 Info.plist 读取）
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - 检查更新

    func check(completion: ((Status) -> Void)? = nil) {
        guard status != .checking else { return }

        status = .checking

        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            status = .error("无效的更新地址")
            completion?(status)
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 403 {
                        self.status = .error("API 限流，稍后再试")
                        completion?(self.status)
                        return
                    }
                }

                if error != nil {
                    self.status = .error("网络不可达")
                    completion?(self.status)
                    return
                }

                guard let data else {
                    self.status = .error("无响应数据")
                    completion?(self.status)
                    return
                }

                self.parseRelease(data, completion: completion)
            }
        }.resume()
    }

    // MARK: - 解析

    private func parseRelease(_ data: Data, completion: ((Status) -> Void)?) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                status = .error("数据格式异常")
                completion?(status)
                return
            }

            guard let tagName = json["tag_name"] as? String,
                  let htmlUrlStr = json["html_url"] as? String else {
                status = .error("未找到发布信息")
                completion?(status)
                return
            }

            let latest = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let url = URL(string: htmlUrlStr)

            if isNewer(latest, than: currentVersion) {
                status = .updateAvailable(current: currentVersion, latest: latest, url: url)
            } else {
                status = .upToDate(current: currentVersion)
            }
            completion?(status)
        } catch {
            status = .error("解析失败")
            completion?(status)
        }
    }

    // MARK: - 版本比较

    /// 简单数值版本比较：比较 a.x.y 和 b.x.y
    private func isNewer(_ versionA: String, than versionB: String) -> Bool {
        let partsA = versionA.split(separator: ".").compactMap { Int($0) }
        let partsB = versionB.split(separator: ".").compactMap { Int($0) }

        let maxLen = max(partsA.count, partsB.count)
        let normalizedA = partsA + Array(repeating: 0, count: maxLen - partsA.count)
        let normalizedB = partsB + Array(repeating: 0, count: maxLen - partsB.count)

        for i in 0..<maxLen {
            if normalizedA[i] > normalizedB[i] { return true }
            if normalizedA[i] < normalizedB[i] { return false }
        }
        return false
    }
}