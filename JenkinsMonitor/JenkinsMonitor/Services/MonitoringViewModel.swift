import Foundation
import Observation

/// 负责任务列表刷新、自动轮询与选中态管理。
@MainActor
@Observable
final class MonitoringViewModel {
    private(set) var servers: [ServerConfiguration] = []
    private(set) var activeServer: ServerConfiguration?
    private(set) var serverInfo: JenkinsServerInfo?
    private(set) var jobs: [JenkinsJob] = []
    private(set) var jobsByServerID: [UUID: [JenkinsJob]] = [:]
    private(set) var serverInfoByID: [UUID: JenkinsServerInfo] = [:]
    private(set) var instanceErrors: [UUID: String] = [:]
    private(set) var selectedServerID: UUID?
    private(set) var selectedJob: JenkinsJob?
    private(set) var builds: [JenkinsBuild] = []
    private(set) var selectedBuild: JenkinsBuild?
    private(set) var isLoadingJobs = false
    private(set) var isLoadingBuilds = false
    private(set) var isTriggeringBuild = false
    private(set) var isSavingServer = false
    private(set) var instanceActionInProgressID: UUID?
    private(set) var instanceActionNotice: String?
    private(set) var restartingServerIDs: Set<UUID> = []
    private(set) var lastRefreshedAt: Date?
    private(set) var errorMessage: String?
    private(set) var connectionBanner: String?

    private(set) var refreshIntervalSeconds: TimeInterval = ServerSettingsStore.defaultRefreshInterval
    var searchText: String = ""

    private let environment: AppEnvironment
    private var refreshTask: Task<Void, Never>?
    private var instanceRecoveryTask: Task<Void, Never>?
    private var client: (any JenkinsAPIClient)?

    init(environment: AppEnvironment? = nil) {
        let environment = environment ?? .live
        self.environment = environment
        self.refreshIntervalSeconds = environment.settingsStore.refreshIntervalSeconds()
    }

    var hasConfiguredServer: Bool {
        !servers.isEmpty
    }

    /// 打开任务/构建页面时使用的站点地址：优先用当前选中任务所属实例，其次用当前实例。
    var browserBaseURL: URL {
        if environment.usesSampleData {
            return .defaultJenkinsBaseURL
        }
        if let selectedServerID,
           let server = servers.first(where: { $0.id == selectedServerID }) {
            return server.baseURL
        }
        return activeServer?.baseURL ?? .defaultJenkinsBaseURL
    }

    func browserURL(for resource: URL) -> URL {
        resource.rebasing(onto: browserBaseURL)
    }

    var allMonitoredJobs: [MonitoredJob] {
        servers.flatMap { server in
            (jobsByServerID[server.id] ?? [])
                .flatMap { $0.flattenedLeafJobs() }
                .map { MonitoredJob(serverID: server.id, job: $0) }
        }
    }

    var filteredMonitoredJobs: [MonitoredJob] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allMonitoredJobs }
        return allMonitoredJobs.filter { item in
            item.job.fullName.localizedCaseInsensitiveContains(query)
                || item.job.name.localizedCaseInsensitiveContains(query)
                || servers.first(where: { $0.id == item.serverID })?.name
                    .localizedCaseInsensitiveContains(query) == true
        }
    }

    var instanceJobGroups: [InstanceJobGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let groups = servers.map { server -> InstanceJobGroup in
            let jobs = (jobsByServerID[server.id] ?? [])
                .flatMap { $0.flattenedLeafJobs() }
                .map { MonitoredJob(serverID: server.id, job: $0) }
                .filter { item in
                    guard !query.isEmpty else { return true }
                    if server.name.localizedCaseInsensitiveContains(query) { return true }
                    return item.job.fullName.localizedCaseInsensitiveContains(query)
                        || item.job.name.localizedCaseInsensitiveContains(query)
                }
            return InstanceJobGroup(
                server: server,
                jobs: jobs,
                isLoading: isLoadingJobs && jobsByServerID[server.id] == nil,
                errorMessage: instanceErrors[server.id]
            )
        }
        if query.isEmpty {
            return groups
        }
        return groups.filter { !$0.jobs.isEmpty || $0.errorMessage != nil || $0.isLoading }
    }

    var overallStatus: BuildResult {
        let statuses = allMonitoredJobs.map(\.job.displayStatus)
        if statuses.contains(.failure) { return .failure }
        if statuses.contains(.unstable) { return .unstable }
        if statuses.contains(.inProgress) { return .inProgress }
        if statuses.contains(.aborted) { return .aborted }
        if statuses.allSatisfy({ $0 == .success || $0 == .notBuilt || $0 == .unknown }) {
            return statuses.contains(.success) ? .success : .unknown
        }
        return .unknown
    }

    var failingJobCount: Int {
        allMonitoredJobs.filter { $0.job.displayStatus == .failure || $0.job.displayStatus == .unstable }.count
    }

    func bootstrap() {
        reloadServersFromStore()
        if environment.usesSampleData, servers.isEmpty {
            servers = [SampleData.serverConfiguration]
            activeServer = SampleData.serverConfiguration
            rebuildClient()
        }
        Task { await refreshAll(force: true) }
        startAutoRefresh()
    }

    /// 无需真实 Jenkins 即可浏览界面（使用 Mock 客户端）。
    func enableSampleDataMode() {
        environment.enableSampleData()
        servers = [SampleData.serverConfiguration]
        activeServer = SampleData.serverConfiguration
        errorMessage = nil
        connectionBanner = "当前为样例数据模式"
        rebuildClient()
        Task { await refreshAll(force: true) }
    }

    func reloadServersFromStore() {
        servers = environment.settingsStore.loadServers()
        if let activeID = environment.settingsStore.activeServerID(),
           let match = servers.first(where: { $0.id == activeID }) {
            activeServer = match
        } else {
            activeServer = servers.first
        }
        let validIDs = Set(servers.map(\.id))
        jobsByServerID = jobsByServerID.filter { validIDs.contains($0.key) }
        serverInfoByID = serverInfoByID.filter { validIDs.contains($0.key) }
        instanceErrors = instanceErrors.filter { validIDs.contains($0.key) }
        rebuildClient()
    }

    func selectServer(_ server: ServerConfiguration) {
        activeServer = server
        environment.settingsStore.setActiveServerID(server.id)
        selectedJob = nil
        selectedServerID = nil
        selectedBuild = nil
        builds = []
        serverInfo = serverInfoByID[server.id]
        jobs = jobsByServerID[server.id] ?? []
        rebuildClient()
        Task { await refreshAll(force: true) }
    }

    func clearError() {
        errorMessage = nil
    }

    func saveServer(_ configuration: ServerConfiguration, makeActive: Bool = true) async -> Bool {
        isSavingServer = true
        errorMessage = nil
        defer { isSavingServer = false }

        do {
            let tokenToProbe: String
            if let token = configuration.userPassword, !token.isEmpty {
                tokenToProbe = token
            } else {
                let existing = try environment.settingsStore.userPassword(for: configuration)
                guard let existing, !existing.isEmpty else {
                    errorMessage = JenkinsAPIError.missingCredentials.localizedDescription
                    return false
                }
                tokenToProbe = existing
            }

            // 真实保存时退出样例模式并校验连通性
            environment.disableSampleData()
            let probe = LiveJenkinsAPIClient(
                baseURL: configuration.baseURL,
                username: configuration.username,
                userPassword: tokenToProbe
            )
            _ = try await probe.testConnection()

            try environment.settingsStore.save(server: configuration)
            reloadServersFromStore()
            if makeActive {
                selectServer(
                    servers.first(where: { $0.id == configuration.id }) ?? configuration
                )
            } else {
                Task { await refreshAll(force: true) }
            }
            connectionBanner = "已连接到 \(configuration.displayHost)"
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func moveServers(from source: IndexSet, to destination: Int) {
        guard servers.count > 1 else { return }
        var reordered = servers
        reordered.move(fromOffsets: source, toOffset: destination)
        persistServerOrder(reordered)
    }

    func moveServer(id: UUID, onto targetID: UUID) {
        guard id != targetID,
              let from = servers.firstIndex(where: { $0.id == id }),
              let to = servers.firstIndex(where: { $0.id == targetID }) else { return }
        moveServers(from: IndexSet(integer: from), to: from < to ? to + 1 : to)
    }

    func saveServerOrder(_ reordered: [ServerConfiguration]) {
        persistServerOrder(reordered)
    }

    private func persistServerOrder(_ reordered: [ServerConfiguration]) {
        servers = reordered
        do {
            try environment.settingsStore.replaceServers(servers)
        } catch {
            reloadServersFromStore()
            errorMessage = error.localizedDescription
        }
    }

    func deleteServer(_ server: ServerConfiguration) {
        do {
            try environment.settingsStore.delete(serverID: server.id)
            jobsByServerID[server.id] = nil
            serverInfoByID[server.id] = nil
            instanceErrors[server.id] = nil
            if instanceActionInProgressID == server.id {
                instanceActionInProgressID = nil
            }
            instanceRecoveryTask?.cancel()
            restartingServerIDs.remove(server.id)
            if selectedServerID == server.id {
                selectedJob = nil
                selectedServerID = nil
                selectedBuild = nil
                builds = []
            }
            reloadServersFromStore()
            jobs = activeServer.flatMap { jobsByServerID[$0.id] } ?? []
            serverInfo = activeServer.flatMap { serverInfoByID[$0.id] }
            if !servers.isEmpty {
                Task { await refreshAll(force: true) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var selectedMonitoredJobID: String? {
        guard let selectedJob, let selectedServerID else { return nil }
        return MonitoredJob(serverID: selectedServerID, job: selectedJob).id
    }

    /// 尚无选中任务时，默认选中当前实例（否则第一个实例）下的第一个任务。
    private func selectDefaultJobIfNeeded() {
        guard selectedJob == nil else { return }
        if let activeServer,
           let firstOnActive = allMonitoredJobs.first(where: { $0.serverID == activeServer.id }) {
            selectJob(firstOnActive)
            return
        }
        if let first = allMonitoredJobs.first {
            selectJob(first)
        }
    }

    func selectJob(id: String?) {
        guard let id else {
            selectJob(nil)
            return
        }
        selectJob(filteredMonitoredJobs.first { $0.id == id })
    }

    func selectJob(_ item: MonitoredJob?) {
        selectedJob = item?.job
        selectedServerID = item?.serverID
        selectedBuild = nil
        builds = []
        if let item, let server = servers.first(where: { $0.id == item.serverID }) {
            if activeServer?.id != server.id {
                activeServer = server
                environment.settingsStore.setActiveServerID(server.id)
                rebuildClient()
            }
            serverInfo = serverInfoByID[server.id]
            jobs = jobsByServerID[server.id] ?? []
        }
        guard item != nil else { return }
        Task { await refreshBuilds() }
    }

    func selectBuild(_ build: JenkinsBuild?) {
        selectedBuild = build
    }

    func selectBuild(number: Int?) {
        guard let number else {
            selectBuild(nil)
            return
        }
        selectBuild(builds.first { $0.number == number })
    }

    func refreshAll(force: Bool = false) async {
        let targets = servers
        guard !targets.isEmpty else {
            jobs = []
            jobsByServerID = [:]
            serverInfoByID = [:]
            instanceErrors = [:]
            serverInfo = nil
            return
        }

        if isLoadingJobs, !force { return }
        isLoadingJobs = true
        errorMessage = nil
        defer { isLoadingJobs = false }

        struct InstanceResult: Sendable {
            let id: UUID
            var info: JenkinsServerInfo?
            var jobs: [JenkinsJob]
            var error: String?
        }

        var prepared: [(server: ServerConfiguration, client: (any JenkinsAPIClient)?, error: String?)] = []
        for server in targets {
            do {
                prepared.append((server, try environment.makeClient(for: server), nil))
            } catch {
                prepared.append((server, nil, error.localizedDescription))
            }
        }

        let results = await withTaskGroup(of: InstanceResult.self, returning: [InstanceResult].self) { group in
            for item in prepared {
                group.addTask {
                    if let error = item.error {
                        return InstanceResult(id: item.server.id, info: nil, jobs: [], error: error)
                    }
                    guard let client = item.client else {
                        return InstanceResult(id: item.server.id, info: nil, jobs: [], error: JenkinsAPIError.missingCredentials.localizedDescription)
                    }
                    do {
                        async let info = client.fetchServerInfo()
                        async let jobList = client.fetchJobs()
                        return InstanceResult(
                            id: item.server.id,
                            info: try await info,
                            jobs: try await jobList,
                            error: nil
                        )
                    } catch {
                        return InstanceResult(id: item.server.id, info: nil, jobs: [], error: error.localizedDescription)
                    }
                }
            }

            var collected: [InstanceResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        for result in results {
            if let error = result.error {
                if restartingServerIDs.contains(result.id) {
                    serverInfoByID[result.id] = nil
                    continue
                }
                instanceErrors[result.id] = error
            } else {
                instanceErrors[result.id] = nil
                jobsByServerID[result.id] = result.jobs
                serverInfoByID[result.id] = result.info
                restartingServerIDs.remove(result.id)
            }
        }

        let validIDs = Set(targets.map(\.id))
        jobsByServerID = jobsByServerID.filter { validIDs.contains($0.key) }
        serverInfoByID = serverInfoByID.filter { validIDs.contains($0.key) }
        instanceErrors = instanceErrors.filter { validIDs.contains($0.key) }

        if let activeServer {
            jobs = jobsByServerID[activeServer.id] ?? []
            serverInfo = serverInfoByID[activeServer.id]
        }
        lastRefreshedAt = Date()

        if let selected = selectedJob, let selectedServerID {
            if let updated = jobsByServerID[selectedServerID]?
                .flatMap({ $0.flattenedLeafJobs() })
                .first(where: { $0.fullName == selected.fullName }) {
                selectedJob = updated
                await refreshBuilds()
            } else if instanceErrors[selectedServerID] == nil {
                selectedJob = nil
                self.selectedServerID = nil
                builds = []
                selectedBuild = nil
            }
        }

        selectDefaultJobIfNeeded()

        let failed = instanceErrors
            .filter { !restartingServerIDs.contains($0.key) }
            .values
            .compactMap { $0 }
        if failed.count == targets.count, let first = failed.first {
            errorMessage = first
        } else if failed.count == 1, let first = failed.first {
            errorMessage = first
        } else if failed.count > 1 {
            errorMessage = "\(failed.count) 个实例刷新失败。"
        }
    }

    func refreshBuilds() async {
        guard let job = selectedJob, let selectedServerID else { return }
        guard let server = servers.first(where: { $0.id == selectedServerID }) else { return }

        let buildClient: (any JenkinsAPIClient)?
        do {
            buildClient = try environment.makeClient(for: server)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        guard let buildClient else { return }

        isLoadingBuilds = true
        defer { isLoadingBuilds = false }
        do {
            let list = try await buildClient.fetchBuilds(jobFullName: job.fullName, limit: 30)
            // 若刷新期间已切换到其他任务，丢弃过期结果。
            guard self.selectedJob?.fullName == job.fullName,
                  self.selectedServerID == selectedServerID else { return }
            builds = list
            if let selectedBuild,
               let updated = list.first(where: { $0.number == selectedBuild.number }) {
                self.selectedBuild = updated
            } else if selectedBuild == nil {
                selectedBuild = list.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 使用任务的默认参数触发一次构建；无参数任务则直接 build。
    func triggerDefaultBuild() async {
        guard !isTriggeringBuild else { return }
        guard let job = selectedJob, let selectedServerID else { return }
        guard let server = servers.first(where: { $0.id == selectedServerID }) else { return }

        isTriggeringBuild = true
        errorMessage = nil
        defer { isTriggeringBuild = false }

        do {
            let buildClient = try environment.makeClient(for: server)
            try await buildClient.triggerBuildWithDefaultParameters(jobFullName: job.fullName)
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard self.selectedJob?.fullName == job.fullName,
                  self.selectedServerID == selectedServerID else { return }
            await refreshBuilds()
        } catch {
            errorMessage = "触发构建失败：\(error.localizedDescription)"
        }
    }

    func saveRefreshInterval(_ seconds: TimeInterval) {
        let clamped = min(max(seconds, ServerSettingsStore.minRefreshInterval), ServerSettingsStore.maxRefreshInterval)
        environment.settingsStore.setRefreshIntervalSeconds(clamped)
        refreshIntervalSeconds = clamped
        startAutoRefresh()
    }

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let nanoseconds = UInt64(max(self.refreshIntervalSeconds, ServerSettingsStore.minRefreshInterval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                if Task.isCancelled { return }
                await self.refreshAll(force: true)
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func instanceStatusText(for server: ServerConfiguration) -> String? {
        if instanceActionInProgressID == server.id {
            return "正在执行操作…"
        }
        if restartingServerIDs.contains(server.id) {
            return "正在重启…"
        }
        if let info = serverInfoByID[server.id] {
            return info.quietingDown ? "安静模式" : "运行中"
        }
        if instanceErrors[server.id] != nil {
            return "无法连接"
        }
        return nil
    }

    func availableInstanceActions(for server: ServerConfiguration) -> [JenkinsInstanceAction] {
        if let info = serverInfoByID[server.id], info.quietingDown {
            return [.safeRestart, .restart, .cancelQuietDown, .safeExit]
        }
        return [.safeRestart, .restart, .quietDown, .safeExit]
    }

    func performInstanceAction(_ action: JenkinsInstanceAction, on server: ServerConfiguration) async {
        guard instanceActionInProgressID == nil else { return }
        instanceActionInProgressID = server.id
        instanceActionNotice = nil
        errorMessage = nil
        defer { instanceActionInProgressID = nil }

        do {
            let client = try environment.makeClient(for: server)
            try await client.performInstanceAction(action)
            instanceActionNotice = "\(server.name)：\(action.successMessage)"

            switch action {
            case .safeRestart, .restart:
                instanceRecoveryTask?.cancel()
                instanceRecoveryTask = Task { [weak self] in
                    await self?.watchInstanceRestart(server: server, client: client)
                }
            case .safeExit:
                instanceRecoveryTask?.cancel()
                restartingServerIDs.remove(server.id)
                serverInfoByID[server.id] = nil
                jobsByServerID[server.id] = nil
                instanceErrors[server.id] = "实例已停止。"
                if activeServer?.id == server.id {
                    serverInfo = nil
                    jobs = []
                }
            case .quietDown, .cancelQuietDown:
                if let info = try? await client.fetchServerInfo() {
                    serverInfoByID[server.id] = info
                    if activeServer?.id == server.id {
                        serverInfo = info
                    }
                    instanceErrors[server.id] = nil
                }
            }
        } catch {
            errorMessage = "\(server.name)：\(error.localizedDescription)"
        }
    }

    /// 先等到实例短暂不可达（开始重启），再等到恢复后刷新数据。
    /// 安全重启可能要等当前构建结束，在此之前保持原提示，不误报“已恢复”。
    private func watchInstanceRestart(server: ServerConfiguration, client: any JenkinsAPIClient) async {
        var sawDowntime = false
        for _ in 0..<120 {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            if let info = try? await client.fetchServerInfo() {
                if sawDowntime {
                    restartingServerIDs.remove(server.id)
                    serverInfoByID[server.id] = info
                    instanceErrors[server.id] = nil
                    if activeServer?.id == server.id {
                        serverInfo = info
                    }
                    instanceActionNotice = "\(server.name)：实例已恢复。"
                    await refreshAll(force: true)
                    return
                }
            } else {
                sawDowntime = true
                restartingServerIDs.insert(server.id)
                serverInfoByID[server.id] = nil
                instanceActionNotice = "\(server.name)：实例正在重启…"
                if activeServer?.id == server.id {
                    serverInfo = nil
                }
            }
        }
        if sawDowntime {
            restartingServerIDs.remove(server.id)
            instanceActionNotice = "\(server.name)：重启请求已发出，但尚未恢复，请稍后再刷新。"
        }
    }

    private func rebuildClient() {
        guard let activeServer else {
            client = nil
            return
        }
        do {
            client = try environment.makeClient(for: activeServer)
        } catch {
            client = environment.usesSampleData ? MockJenkinsAPIClient() : nil
            if !environment.usesSampleData {
                errorMessage = error.localizedDescription
            }
        }
    }
}
