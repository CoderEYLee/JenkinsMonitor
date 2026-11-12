import Foundation

/// 持久化服务器配置元数据（不含密码）；密码由 KeychainStore 管理。
@MainActor
final class ServerSettingsStore {
    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let serversKey = "jenkins.servers"
    private let activeServerKey = "jenkins.activeServerID"
    private let refreshIntervalKey = "jenkins.refreshIntervalSeconds"
    static let defaultRefreshInterval: TimeInterval = 30
    static let minRefreshInterval: TimeInterval = 10
    static let maxRefreshInterval: TimeInterval = 3600

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore()
    ) {
        self.defaults = defaults
        self.keychain = keychain
    }

    func loadServers() -> [ServerConfiguration] {
        guard let data = defaults.data(forKey: serversKey) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([PersistedServer].self, from: data)
            return decoded.map {
                ServerConfiguration(
                    id: $0.id,
                    name: $0.name,
                    baseURL: $0.baseURL,
                    username: $0.username,
                    userPassword: nil
                )
            }
        } catch {
            return []
        }
    }

    func activeServerID() -> UUID? {
        guard let raw = defaults.string(forKey: activeServerKey) else { return nil }
        return UUID(uuidString: raw)
    }

    func setActiveServerID(_ id: UUID?) {
        if let id {
            defaults.set(id.uuidString, forKey: activeServerKey)
        } else {
            defaults.removeObject(forKey: activeServerKey)
        }
    }

    func refreshIntervalSeconds() -> TimeInterval {
        let stored: TimeInterval
        if defaults.object(forKey: refreshIntervalKey) != nil {
            stored = defaults.double(forKey: refreshIntervalKey)
        } else {
            stored = Self.defaultRefreshInterval
        }
        return min(max(stored, Self.minRefreshInterval), Self.maxRefreshInterval)
    }

    func setRefreshIntervalSeconds(_ value: TimeInterval) {
        let clamped = min(max(value, Self.minRefreshInterval), Self.maxRefreshInterval)
        defaults.set(clamped, forKey: refreshIntervalKey)
    }

    func save(server: ServerConfiguration) throws {
        var servers = loadServers()
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        try persistMetadata(servers)

        if let password = server.userPassword, !password.isEmpty {
            try keychain.saveToken(password, account: keychainAccount(for: server))
        }

        if activeServerID() == nil {
            setActiveServerID(server.id)
        }
    }

    func replaceServers(_ servers: [ServerConfiguration]) throws {
        try persistMetadata(servers)
    }

    func delete(serverID: UUID) throws {
        var servers = loadServers()
        guard let server = servers.first(where: { $0.id == serverID }) else { return }
        servers.removeAll { $0.id == serverID }
        try persistMetadata(servers)
        try keychain.deleteToken(account: keychainAccount(for: server))
        try keychain.deleteToken(account: legacyKeychainAccount(for: server))
        if activeServerID() == serverID {
            setActiveServerID(servers.first?.id)
        }
    }

    func userPassword(for server: ServerConfiguration) throws -> String? {
        if let password = try keychain.loadToken(account: keychainAccount(for: server)), !password.isEmpty {
            return password
        }
        // 兼容旧版钥匙串账号（uuid.apiToken）。
        if let password = try keychain.loadToken(account: legacyKeychainAccount(for: server)), !password.isEmpty {
            try keychain.saveToken(password, account: keychainAccount(for: server))
            try keychain.deleteToken(account: legacyKeychainAccount(for: server))
            return password
        }
        return nil
    }

    func resolvedConfiguration(for server: ServerConfiguration) throws -> ServerConfiguration {
        var copy = server
        copy.userPassword = try userPassword(for: server)
        return copy
    }

    private func persistMetadata(_ servers: [ServerConfiguration]) throws {
        let payload = servers.map {
            PersistedServer(id: $0.id, name: $0.name, baseURL: $0.baseURL, username: $0.username)
        }
        let data = try JSONEncoder().encode(payload)
        defaults.set(data, forKey: serversKey)
    }

    private func keychainAccount(for server: ServerConfiguration) -> String {
        "\(server.id.uuidString).userPassword"
    }

    private func legacyKeychainAccount(for server: ServerConfiguration) -> String {
        "\(server.id.uuidString).apiToken"
    }
}

private struct PersistedServer: Codable {
    let id: UUID
    let name: String
    let baseURL: URL
    let username: String
}
