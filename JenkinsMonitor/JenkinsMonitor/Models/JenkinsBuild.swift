import Foundation

/// 一次 Jenkins 构建记录。
struct JenkinsBuild: Identifiable, Hashable, Sendable, Codable {
    var id: Int { number }
    let number: Int
    let url: URL
    let result: BuildResult
    let timestamp: Date
    let duration: TimeInterval
    let building: Bool
    let displayName: String?

    var formattedDuration: String {
        if building && duration <= 0 {
            return "进行中…"
        }
        let totalSeconds = Int(duration / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d小时 %d分 %d秒", hours, minutes, seconds)
        }
        if minutes > 0 {
            return String(format: "%d分 %d秒", minutes, seconds)
        }
        return String(format: "%d秒", seconds)
    }

    var formattedTimestamp: String {
        timestamp.formatted(date: .abbreviated, time: .shortened)
    }
}
