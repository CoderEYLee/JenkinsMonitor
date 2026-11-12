import Foundation

/// Jenkins 任务（含文件夹内的嵌套任务）。
struct JenkinsJob: Identifiable, Hashable, Sendable, Codable {
    var id: String { fullName }
    let name: String
    let fullName: String
    let url: URL
    let color: String?
    let isFolder: Bool
    let children: [JenkinsJob]
    let lastBuild: JenkinsBuild?

    var displayStatus: BuildResult {
        if let lastBuild {
            return lastBuild.result
        }
        return BuildResult.fromJenkinsColor(color)
    }

    /// 扁平化展开所有叶子任务（不含文件夹本身）。
    func flattenedLeafJobs() -> [JenkinsJob] {
        if isFolder {
            return children.flatMap { $0.flattenedLeafJobs() }
        }
        return [self]
    }
}

extension BuildResult {
    /// 从 Jenkins `color` 字段推断状态（任务列表常用）。
    static func fromJenkinsColor(_ color: String?) -> BuildResult {
        guard let color else { return .unknown }
        let normalized = color.lowercased()
        if normalized.contains("anime") || normalized.contains("running") {
            return .inProgress
        }
        switch normalized {
        case "blue", "blue_anime", "green", "green_anime":
            return .success
        case "red", "red_anime":
            return .failure
        case "yellow", "yellow_anime":
            return .unstable
        case "aborted", "aborted_anime", "grey", "disabled", "notbuilt", "notbuilt_anime":
            return normalized.contains("aborted") ? .aborted : .notBuilt
        default:
            return .unknown
        }
    }
}

/// 带所属实例的任务，避免不同实例下同名任务冲突。
struct MonitoredJob: Identifiable, Hashable, Sendable {
    var id: String { "\(serverID.uuidString)::\(job.fullName)" }
    let serverID: UUID
    let job: JenkinsJob
}

/// 侧边栏中一个实例及其项目。
struct InstanceJobGroup: Identifiable {
    var id: UUID { server.id }
    let server: ServerConfiguration
    let jobs: [MonitoredJob]
    let isLoading: Bool
    let errorMessage: String?
}
