import Foundation
import SwiftUI

/// Jenkins 构建结果状态。
enum BuildResult: String, Codable, Sendable, CaseIterable, Hashable {
    case success = "SUCCESS"
    case failure = "FAILURE"
    case unstable = "UNSTABLE"
    case aborted = "ABORTED"
    case notBuilt = "NOT_BUILT"
    case inProgress = "IN_PROGRESS"
    case unknown = "UNKNOWN"

    init(jenkinsResult: String?, building: Bool) {
        if building {
            self = .inProgress
            return
        }
        guard let jenkinsResult, let value = BuildResult(rawValue: jenkinsResult) else {
            self = .unknown
            return
        }
        self = value
    }

    var displayName: String {
        switch self {
        case .success: return "成功"
        case .failure: return "失败"
        case .unstable: return "不稳定"
        case .aborted: return "已中止"
        case .notBuilt: return "未构建"
        case .inProgress: return "进行中"
        case .unknown: return "未知"
        }
    }

    var systemImage: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .unstable: return "exclamationmark.triangle.fill"
        case .aborted: return "stop.circle.fill"
        case .notBuilt: return "minus.circle.fill"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .success: return .green
        case .failure: return .red
        case .unstable: return .orange
        case .aborted: return .secondary
        case .notBuilt: return .secondary
        case .inProgress: return .blue
        case .unknown: return .secondary
        }
    }

    /// 是否视为“健康”状态（用于菜单栏总览）。
    var isHealthy: Bool {
        switch self {
        case .success, .notBuilt, .unknown:
            return true
        case .failure, .unstable, .aborted, .inProgress:
            return false
        }
    }
}
