import Foundation

/// Jenkins 服务器基本信息。
struct JenkinsServerInfo: Hashable, Sendable, Codable {
    let mode: String?
    let nodeName: String?
    let nodeDescription: String?
    let description: String?
    let numExecutors: Int?
    let quietingDown: Bool
    let version: String?

    var displayTitle: String {
        if let description, !description.isEmpty {
            return description
        }
        if let nodeName, !nodeName.isEmpty {
            return nodeName
        }
        return "Jenkins 实例"
    }
}
