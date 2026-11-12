import Foundation

/// 用户配置的 Jenkins 服务器连接信息（密钥不落盘，仅保存在 Keychain）。
struct ServerConfiguration: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var baseURL: URL
    var username: String
    /// 仅用于内存中的临时表单；持久化时密码写入 Keychain。
    var userPassword: String?

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: URL,
        username: String,
        userPassword: String? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.username = username
        self.userPassword = userPassword
    }

    var displayHost: String {
        baseURL.host ?? baseURL.absoluteString
    }
}
