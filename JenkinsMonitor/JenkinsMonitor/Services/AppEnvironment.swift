import Foundation

/// 应用依赖注入容器。
@MainActor
final class AppEnvironment {
    let settingsStore: ServerSettingsStore
    private(set) var usesSampleData: Bool

    init(
        settingsStore: ServerSettingsStore? = nil,
        usesSampleData: Bool = false
    ) {
        self.settingsStore = settingsStore ?? ServerSettingsStore()
        self.usesSampleData = usesSampleData
    }

    private static var liveStorage: AppEnvironment?
    static var live: AppEnvironment {
        if let liveStorage { return liveStorage }
        let created = AppEnvironment()
        liveStorage = created
        return created
    }

    static var preview: AppEnvironment {
        AppEnvironment(usesSampleData: true)
    }

    func enableSampleData() {
        usesSampleData = true
    }

    func disableSampleData() {
        usesSampleData = false
    }

    func makeClient(for server: ServerConfiguration) throws -> any JenkinsAPIClient {
        if usesSampleData {
            return MockJenkinsAPIClient()
        }
        let resolved = try settingsStore.resolvedConfiguration(for: server)
        guard let token = resolved.userPassword, !token.isEmpty else {
            throw JenkinsAPIError.missingCredentials
        }
        return LiveJenkinsAPIClient(
            baseURL: resolved.baseURL,
            username: resolved.username,
            userPassword: token
        )
    }
}
