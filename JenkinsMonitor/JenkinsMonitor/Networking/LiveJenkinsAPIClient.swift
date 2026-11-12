import Foundation

/// 基于 URLSession 的 Jenkins Remote Access API 客户端。
/// 使用 Basic Auth（用户名 + 密码），并缓存 CSRF Crumb 供后续写操作使用。
actor LiveJenkinsAPIClient: JenkinsAPIClient {
    private let baseURL: URL
    private let username: String
    private let userPassword: String
    private let session: URLSession

    private var cachedCrumb: JenkinsDTO.Crumb?

    init(
        baseURL: URL,
        username: String,
        userPassword: String,
        session: URLSession = .shared
    ) {
        let normalized: URL
        if baseURL.absoluteString.hasSuffix("/") {
            normalized = baseURL
        } else {
            normalized = URL(string: baseURL.absoluteString + "/") ?? baseURL
        }
        self.baseURL = normalized
        self.username = username
        self.userPassword = userPassword
        self.session = session
    }

    func testConnection() async throws -> JenkinsServerInfo {
        try await fetchServerInfo()
    }

    func fetchServerInfo() async throws -> JenkinsServerInfo {
        let (data, response) = try await perform(
            path: "api/json",
            queryItems: [
                URLQueryItem(
                    name: "tree",
                    value: "mode,nodeName,nodeDescription,description,numExecutors,quietingDown"
                )
            ]
        )
        let dto = try decode(JenkinsDTO.ServerInfo.self, from: data)
        let version = response.value(forHTTPHeaderField: "X-Jenkins")
        return dto.toDomain(version: version)
    }

    func fetchJobs() async throws -> [JenkinsJob] {
        let tree =
            "jobs[name,url,color,_class,lastBuild[number,url,result,timestamp,duration,building,displayName],jobs[name,url,color,_class,lastBuild[number,url,result,timestamp,duration,building,displayName],jobs[name,url,color,_class,lastBuild[number,url,result,timestamp,duration,building,displayName]]]]"
        let (data, _) = try await perform(
            path: "api/json",
            queryItems: [URLQueryItem(name: "tree", value: tree)]
        )
        let dto = try decode(JenkinsDTO.JobList.self, from: data)
        return (dto.jobs ?? []).map { $0.toDomain(parentFullName: nil, configuredBaseURL: baseURL) }
    }

    func fetchBuilds(jobFullName: String, limit: Int) async throws -> [JenkinsBuild] {
        let path = jobAPIPath(fullName: jobFullName) + "api/json"
        let tree =
            "builds[number,url,result,timestamp,duration,building,displayName]{0,\(max(limit, 1))}"
        let (data, _) = try await perform(
            path: path,
            queryItems: [URLQueryItem(name: "tree", value: tree)]
        )
        let dto = try decode(JenkinsDTO.BuildList.self, from: data)
        return (dto.builds ?? []).map { $0.toDomain(configuredBaseURL: baseURL) }
    }

    func fetchBuild(jobFullName: String, number: Int) async throws -> JenkinsBuild {
        let path = jobAPIPath(fullName: jobFullName) + "\(number)/api/json"
        let (data, _) = try await perform(
            path: path,
            queryItems: [
                URLQueryItem(
                    name: "tree",
                    value: "number,url,result,timestamp,duration,building,displayName"
                )
            ]
        )
        let dto = try decode(JenkinsDTO.Build.self, from: data)
        return dto.toDomain(configuredBaseURL: baseURL)
    }

    /// 主动刷新 CSRF Crumb，供后续触发构建等写操作使用。
    func refreshCrumb() async throws {
        cachedCrumb = nil
        _ = try await ensureCrumb()
    }

    func performInstanceAction(_ action: JenkinsInstanceAction) async throws {
        // 先单独取 crumb，避免把取 crumb 失败误判成“实例已开始关闭”。
        let crumb = try await ensureCrumb()
        let url = try makeURL(path: action.path, queryItems: [])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(basicAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue(crumb.crumb, forHTTPHeaderField: crumb.crumbRequestField)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data()

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JenkinsAPIError.transport("无效的服务器响应。")
            }
            if (200..<400).contains(http.statusCode) {
                return
            }
            if action.expectsShutdown && (http.statusCode == 502 || http.statusCode == 503) {
                return
            }
            try validate(http: http, data: data)
        } catch let error as JenkinsAPIError {
            throw error
        } catch {
            if action.expectsShutdown {
                return
            }
            throw JenkinsAPIError.transport(error.localizedDescription)
        }
    }

    func triggerBuildWithDefaultParameters(jobFullName: String) async throws {
        let jobPath = jobAPIPath(fullName: jobFullName)
        let (data, _) = try await perform(
            path: jobPath + "api/json",
            queryItems: [
                URLQueryItem(
                    name: "tree",
                    value: "property[parameterDefinitions[name,defaultParameterValue[value]]]"
                )
            ]
        )
        let properties = try decode(JenkinsDTO.JobProperties.self, from: data)
        let parameters = properties.defaultParameters
        let action = parameters.isEmpty ? "build" : "buildWithParameters"
        try await postForm(path: jobPath + action, fields: parameters)
    }

    // MARK: - Private

    private func postForm(path: String, fields: [(name: String, value: String)]) async throws {
        func send() async throws {
            let crumb = try await ensureCrumb()
            let url = try makeURL(path: path, queryItems: [])
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(basicAuthHeader(), forHTTPHeaderField: "Authorization")
            request.setValue(crumb.crumb, forHTTPHeaderField: crumb.crumbRequestField)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formURLEncoded(fields)

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw JenkinsAPIError.transport("无效的服务器响应。")
                }
                if (200..<400).contains(http.statusCode) {
                    return
                }
                try validate(http: http, data: data)
            } catch let error as JenkinsAPIError {
                throw error
            } catch {
                throw JenkinsAPIError.transport(error.localizedDescription)
            }
        }

        do {
            try await send()
        } catch JenkinsAPIError.forbidden {
            cachedCrumb = nil
            try await send()
        }
    }

    private static func formURLEncoded(_ fields: [(name: String, value: String)]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encode(_ raw: String) -> String {
            raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
        }
        return fields
            .map { encode($0.name) + "=" + encode($0.value) }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private func jobAPIPath(fullName: String) -> String {
        let segments = fullName
            .split(separator: "/")
            .map(String.init)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }
        return segments.map { "job/\($0)/" }.joined()
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(string: base + "/" + trimmedPath)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw JenkinsAPIError.invalidURL
        }
        return url
    }

    private func perform(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        includeCrumb: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        let url = try makeURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(basicAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if includeCrumb {
            let crumb = try await ensureCrumb()
            request.setValue(crumb.crumb, forHTTPHeaderField: crumb.crumbRequestField)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JenkinsAPIError.transport("无效的服务器响应。")
            }
            try validate(http: http, data: data)
            return (data, http)
        } catch let error as JenkinsAPIError {
            throw error
        } catch {
            throw JenkinsAPIError.transport(error.localizedDescription)
        }
    }

    private func ensureCrumb() async throws -> JenkinsDTO.Crumb {
        if let cachedCrumb {
            return cachedCrumb
        }
        do {
            let (data, _) = try await perform(path: "crumbIssuer/api/json", includeCrumb: false)
            let crumb = try decode(JenkinsDTO.Crumb.self, from: data)
            cachedCrumb = crumb
            return crumb
        } catch JenkinsAPIError.notFound {
            throw JenkinsAPIError.crumbRequired
        }
    }

    private func basicAuthHeader() -> String {
        let raw = "\(username):\(userPassword)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private func validate(http: HTTPURLResponse, data: Data) throws {
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw JenkinsAPIError.unauthorized
        case 403:
            throw JenkinsAPIError.forbidden
        case 404:
            throw JenkinsAPIError.notFound
        default:
            let message = String(data: data, encoding: .utf8)
            throw JenkinsAPIError.serverError(statusCode: http.statusCode, message: message)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw JenkinsAPIError.decodingFailed(error.localizedDescription)
        }
    }
}
