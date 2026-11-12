import Foundation

/// 样例数据客户端：无需真实 Jenkins 即可预览与编译运行 UI。
struct MockJenkinsAPIClient: JenkinsAPIClient {
    var latencyNanoseconds: UInt64 = 300_000_000
    var shouldFail: Bool = false

    func testConnection() async throws -> JenkinsServerInfo {
        try await fetchServerInfo()
    }

    func fetchServerInfo() async throws -> JenkinsServerInfo {
        try await delay()
        try failIfNeeded()
        return SampleData.serverInfo
    }

    func fetchJobs() async throws -> [JenkinsJob] {
        try await delay()
        try failIfNeeded()
        return SampleData.jobs
    }

    func fetchBuilds(jobFullName: String, limit: Int) async throws -> [JenkinsBuild] {
        try await delay()
        try failIfNeeded()
        let builds = SampleData.builds(for: jobFullName)
        return Array(builds.prefix(limit))
    }

    func fetchBuild(jobFullName: String, number: Int) async throws -> JenkinsBuild {
        try await delay()
        try failIfNeeded()
        guard let build = SampleData.builds(for: jobFullName).first(where: { $0.number == number }) else {
            throw JenkinsAPIError.notFound
        }
        return build
    }

    func performInstanceAction(_ action: JenkinsInstanceAction) async throws {
        try await delay()
        try failIfNeeded()
    }

    func triggerBuildWithDefaultParameters(jobFullName: String) async throws {
        try await delay()
        try failIfNeeded()
    }

    private func delay() async throws {
        if latencyNanoseconds > 0 {
            try await Task.sleep(nanoseconds: latencyNanoseconds)
        }
    }

    private func failIfNeeded() throws {
        if shouldFail {
            throw JenkinsAPIError.transport("模拟网络错误")
        }
    }
}
