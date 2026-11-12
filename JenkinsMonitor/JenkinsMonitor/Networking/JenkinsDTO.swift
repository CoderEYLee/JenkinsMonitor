import Foundation

/// Jenkins JSON 解码中间层（与公开 API 字段对齐）。
enum JenkinsDTO {
    struct ServerInfo: Decodable {
        let mode: String?
        let nodeName: String?
        let nodeDescription: String?
        let description: String?
        let numExecutors: Int?
        let quietingDown: Bool?
    }

    struct Crumb: Decodable {
        let crumb: String
        let crumbRequestField: String
    }

    struct JobList: Decodable {
        let jobs: [Job]?
    }

    struct Job: Decodable {
        let name: String
        let url: String
        let color: String?
        let _class: String?
        let jobs: [Job]?
        let lastBuild: Build?
    }

    struct BuildList: Decodable {
        let builds: [Build]?
    }

    struct Build: Decodable {
        let number: Int
        let url: String
        let result: String?
        let timestamp: Double?
        let duration: Double?
        let building: Bool?
        let displayName: String?
    }

    struct JobProperties: Decodable {
        let property: [JobProperty]?

        var defaultParameters: [(name: String, value: String)] {
            (property ?? [])
                .flatMap { $0.parameterDefinitions ?? [] }
                .compactMap { definition in
                    let name = definition.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !name.isEmpty else { return nil }
                    let value = definition.defaultParameterValue?.value?.stringValue ?? ""
                    return (name, value)
                }
        }
    }

    struct JobProperty: Decodable {
        let parameterDefinitions: [ParameterDefinition]?
    }

    struct ParameterDefinition: Decodable {
        let name: String?
        let defaultParameterValue: DefaultParameterValue?
    }

    struct DefaultParameterValue: Decodable {
        let value: FlexibleJSONValue?
    }

    enum FlexibleJSONValue: Decodable {
        case string(String)
        case other

        var stringValue: String {
            switch self {
            case .string(let value):
                return value
            case .other:
                return ""
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .string("")
                return
            }
            if let value = try? container.decode(String.self) {
                self = .string(value)
                return
            }
            if let value = try? container.decode(Bool.self) {
                self = .string(value ? "true" : "false")
                return
            }
            if let value = try? container.decode(Int.self) {
                self = .string(String(value))
                return
            }
            if let value = try? container.decode(Double.self) {
                self = .string(String(value))
                return
            }
            self = .other
        }
    }
}

extension JenkinsDTO.ServerInfo {
    func toDomain(version: String?) -> JenkinsServerInfo {
        JenkinsServerInfo(
            mode: mode,
            nodeName: nodeName,
            nodeDescription: nodeDescription,
            description: description,
            numExecutors: numExecutors,
            quietingDown: quietingDown ?? false,
            version: version
        )
    }
}

extension JenkinsDTO.Job {
    func toDomain(parentFullName: String?, configuredBaseURL: URL? = nil) -> JenkinsJob {
        let fullName: String
        if let parentFullName, !parentFullName.isEmpty {
            fullName = "\(parentFullName)/\(name)"
        } else {
            fullName = name
        }

        let folder = isFolder
        let childJobs = (jobs ?? []).map { $0.toDomain(parentFullName: fullName, configuredBaseURL: configuredBaseURL) }
        let last = lastBuild?.toDomain(configuredBaseURL: configuredBaseURL)

        return JenkinsJob(
            name: name,
            fullName: fullName,
            url: URL.jenkinsResource(from: url, configuredBaseURL: configuredBaseURL),
            color: color,
            isFolder: folder,
            children: childJobs,
            lastBuild: last
        )
    }

    private var isFolder: Bool {
        if let _class, _class.lowercased().contains("folder") {
            return true
        }
        return jobs != nil
    }
}

extension JenkinsDTO.Build {
    func toDomain(configuredBaseURL: URL? = nil) -> JenkinsBuild {
        let building = building ?? false
        let result = BuildResult(jenkinsResult: result, building: building)
        let ts = Date(timeIntervalSince1970: (timestamp ?? 0) / 1000.0)
        return JenkinsBuild(
            number: number,
            url: URL.jenkinsResource(from: url, configuredBaseURL: configuredBaseURL),
            result: result,
            timestamp: ts,
            duration: duration ?? 0,
            building: building,
            displayName: displayName
        )
    }
}

extension URL {
    /// 未配置服务器地址时，浏览器打开使用的默认 Jenkins 地址。
    static let defaultJenkinsBaseURL = URL(string: "http://localhost:8080/")!

    /// 用用户配置的服务器地址替换接口返回 URL 的站点部分，保留任务/构建路径。
    static func jenkinsResource(from raw: String, configuredBaseURL: URL?) -> URL {
        let base = configuredBaseURL ?? .defaultJenkinsBaseURL
        guard let parsed = URL(string: raw) else {
            return base
        }
        return parsed.rebasing(onto: base)
    }

    func rebasing(onto base: URL) -> URL {
        guard var destination = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        guard let source = URLComponents(url: base, resolvingAgainstBaseURL: false),
              source.host != nil else {
            return self
        }

        destination.scheme = source.scheme
        destination.host = source.host
        destination.port = source.port
        destination.user = source.user
        destination.password = source.password

        let basePath = Self.trimmedJenkinsPath(source.path)
        let resourcePath = destination.path.isEmpty ? "/" : destination.path
        if !basePath.isEmpty {
            let alreadyPrefixed = resourcePath == basePath || resourcePath.hasPrefix(basePath + "/")
            if !alreadyPrefixed {
                let suffix = resourcePath.hasPrefix("/") ? resourcePath : "/" + resourcePath
                destination.path = basePath + suffix
            }
        }

        return destination.url ?? self
    }

    private static func trimmedJenkinsPath(_ path: String) -> String {
        if path.isEmpty || path == "/" {
            return ""
        }
        var result = path
        if result.hasSuffix("/") {
            result.removeLast()
        }
        if !result.hasPrefix("/") {
            result = "/" + result
        }
        return result
    }
}
