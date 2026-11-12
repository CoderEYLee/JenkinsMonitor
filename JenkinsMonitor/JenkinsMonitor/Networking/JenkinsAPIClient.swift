import Foundation

/// Jenkins 实例管理操作（需要 Administer 权限）。
enum JenkinsInstanceAction: String, CaseIterable, Identifiable, Sendable {
    case safeRestart
    case restart
    case quietDown
    case cancelQuietDown
    case safeExit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .safeRestart: return "安全重启"
        case .restart: return "立即重启"
        case .quietDown: return "进入安静模式"
        case .cancelQuietDown: return "取消安静模式"
        case .safeExit: return "安全停止"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .safeRestart:
            return "会在当前构建结束后重启该实例，期间监控会暂时中断。"
        case .restart:
            return "会立即重启该实例，正在运行的构建可能会被中断。"
        case .quietDown:
            return "进入安静模式后，该实例将不再接收新的构建。"
        case .cancelQuietDown:
            return "取消安静模式后，该实例会重新接收新的构建。"
        case .safeExit:
            return "会在当前构建结束后关闭该实例。关闭后无法通过接口再启动，需要在机器上手动启动。"
        }
    }

    var path: String {
        switch self {
        case .safeRestart: return "safeRestart"
        case .restart: return "restart"
        case .quietDown: return "quietDown"
        case .cancelQuietDown: return "cancelQuietDown"
        case .safeExit: return "safeExit"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .safeRestart, .restart, .safeExit: return true
        case .quietDown, .cancelQuietDown: return false
        }
    }

    /// 重启/停止时，Jenkins 可能在响应前开始关闭，503 或连接中断视为请求已生效。
    var expectsShutdown: Bool {
        switch self {
        case .safeRestart, .restart, .safeExit: return true
        case .quietDown, .cancelQuietDown: return false
        }
    }

    var successMessage: String {
        switch self {
        case .safeRestart: return "已发出安全重启请求，将在构建结束后重启。"
        case .restart: return "已发出立即重启请求。"
        case .quietDown: return "已进入安静模式。"
        case .cancelQuietDown: return "已取消安静模式。"
        case .safeExit: return "已发出安全停止请求，将在构建结束后关闭。"
        }
    }
}

/// Jenkins Remote Access API 客户端协议，便于预览与单元测试注入样例数据。
protocol JenkinsAPIClient: Sendable {
    func fetchServerInfo() async throws -> JenkinsServerInfo
    func fetchJobs() async throws -> [JenkinsJob]
    func fetchBuilds(jobFullName: String, limit: Int) async throws -> [JenkinsBuild]
    func fetchBuild(jobFullName: String, number: Int) async throws -> JenkinsBuild
    func testConnection() async throws -> JenkinsServerInfo
    func performInstanceAction(_ action: JenkinsInstanceAction) async throws
    func triggerBuildWithDefaultParameters(jobFullName: String) async throws
}

extension JenkinsAPIClient {
    func fetchBuilds(jobFullName: String) async throws -> [JenkinsBuild] {
        try await fetchBuilds(jobFullName: jobFullName, limit: 20)
    }
}
