import Foundation

enum SampleData {
    static let serverInfo = JenkinsServerInfo(
        mode: "NORMAL",
        nodeName: "演示节点",
        nodeDescription: "Jenkins Monitor 样例数据",
        description: "演示 Jenkins 实例",
        numExecutors: 4,
        quietingDown: false,
        version: "2.462.1"
    )

    static let serverConfiguration = ServerConfiguration(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        name: "演示实例",
        baseURL: URL(string: "https://jenkins.example.com")!,
        username: "demo",
        userPassword: nil
    )

    static var jobs: [JenkinsJob] {
        let now = Date()
        return [
            JenkinsJob(
                name: "mobile-ios",
                fullName: "mobile-ios",
                url: URL(string: "https://jenkins.example.com/job/mobile-ios/")!,
                color: "blue",
                isFolder: false,
                children: [],
                lastBuild: JenkinsBuild(
                    number: 128,
                    url: URL(string: "https://jenkins.example.com/job/mobile-ios/128/")!,
                    result: .success,
                    timestamp: now.addingTimeInterval(-3600),
                    duration: 245_000,
                    building: false,
                    displayName: "#128"
                )
            ),
            JenkinsJob(
                name: "backend",
                fullName: "backend",
                url: URL(string: "https://jenkins.example.com/job/backend/")!,
                color: nil,
                isFolder: true,
                children: [
                    JenkinsJob(
                        name: "api-gateway",
                        fullName: "backend/api-gateway",
                        url: URL(string: "https://jenkins.example.com/job/backend/job/api-gateway/")!,
                        color: "red",
                        isFolder: false,
                        children: [],
                        lastBuild: JenkinsBuild(
                            number: 56,
                            url: URL(string: "https://jenkins.example.com/job/backend/job/api-gateway/56/")!,
                            result: .failure,
                            timestamp: now.addingTimeInterval(-1800),
                            duration: 92_000,
                            building: false,
                            displayName: "#56"
                        )
                    ),
                    JenkinsJob(
                        name: "auth-service",
                        fullName: "backend/auth-service",
                        url: URL(string: "https://jenkins.example.com/job/backend/job/auth-service/")!,
                        color: "yellow_anime",
                        isFolder: false,
                        children: [],
                        lastBuild: JenkinsBuild(
                            number: 44,
                            url: URL(string: "https://jenkins.example.com/job/backend/job/auth-service/44/")!,
                            result: .inProgress,
                            timestamp: now.addingTimeInterval(-120),
                            duration: 0,
                            building: true,
                            displayName: "#44"
                        )
                    )
                ],
                lastBuild: nil
            ),
            JenkinsJob(
                name: "docs-site",
                fullName: "docs-site",
                url: URL(string: "https://jenkins.example.com/job/docs-site/")!,
                color: "aborted",
                isFolder: false,
                children: [],
                lastBuild: JenkinsBuild(
                    number: 12,
                    url: URL(string: "https://jenkins.example.com/job/docs-site/12/")!,
                    result: .aborted,
                    timestamp: now.addingTimeInterval(-86400),
                    duration: 15_000,
                    building: false,
                    displayName: "#12"
                )
            ),
            JenkinsJob(
                name: "nightly-regression",
                fullName: "nightly-regression",
                url: URL(string: "https://jenkins.example.com/job/nightly-regression/")!,
                color: "yellow",
                isFolder: false,
                children: [],
                lastBuild: JenkinsBuild(
                    number: 301,
                    url: URL(string: "https://jenkins.example.com/job/nightly-regression/301/")!,
                    result: .unstable,
                    timestamp: now.addingTimeInterval(-7200),
                    duration: 1_800_000,
                    building: false,
                    displayName: "#301"
                )
            )
        ]
    }

    static func builds(for jobFullName: String) -> [JenkinsBuild] {
        let baseURL = URL(string: "https://jenkins.example.com/job/\(jobFullName.replacingOccurrences(of: "/", with: "/job/"))/")!
        let now = Date()
        let results: [BuildResult] = [.success, .failure, .unstable, .success, .aborted, .inProgress]
        return (0..<8).map { index in
            let number = 100 - index
            let result = results[index % results.count]
            let building = result == .inProgress
            return JenkinsBuild(
                number: number,
                url: baseURL.appendingPathComponent("\(number)/"),
                result: result,
                timestamp: now.addingTimeInterval(Double(-index) * 3600),
                duration: building ? 0 : Double((60 + index * 17) * 1000),
                building: building,
                displayName: "#\(number)"
            )
        }
    }
}
