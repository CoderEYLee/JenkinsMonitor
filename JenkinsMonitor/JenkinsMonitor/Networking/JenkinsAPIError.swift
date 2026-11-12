import Foundation

enum JenkinsAPIError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case serverError(statusCode: Int, message: String?)
    case decodingFailed(String)
    case transport(String)
    case missingCredentials
    case crumbRequired

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "实例地址无效。"
        case .unauthorized:
            return "认证失败，请检查用户名或密码。"
        case .forbidden:
            return "没有权限访问该资源。"
        case .notFound:
            return "未找到请求的资源。"
        case .serverError(let statusCode, let message):
            if let message, !message.isEmpty {
                return "服务器错误（\(statusCode)）：\(message)"
            }
            return "服务器错误（HTTP \(statusCode)）。"
        case .decodingFailed(let detail):
            return "解析 Jenkins 响应失败：\(detail)"
        case .transport(let detail):
            return "网络请求失败：\(detail)"
        case .missingCredentials:
            return "缺少实例凭证。"
        case .crumbRequired:
            return "需要 CSRF Crumb，但未能获取。"
        }
    }
}
