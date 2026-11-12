import SwiftUI

struct OnboardingView: View {
    @Bindable var viewModel: MonitoringViewModel
    @State private var name: String = "我的 Jenkins"
    @State private var baseURLString: String = ""
    @State private var username: String = ""
    @State private var userPassword: String = ""
    @State private var localError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Jenkins Monitor")
                            .font(.largeTitle.weight(.bold))
                        Text("连接你的 Jenkins 实例，实时查看任务与构建状态。密码将安全保存在系统钥匙串中。")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                }

                Section("实例信息") {
                    TextField("显示名称", text: $name, prompt: Text("Jenkins1"))
                        .multilineTextAlignment(.trailing)
                    TextField(
                        "实例地址",
                        text: $baseURLString,
                        prompt: Text(verbatim: "默认 http://127.0.0.1:8080/")
                    )
                    .textContentType(.URL)
                    .multilineTextAlignment(.trailing)
                    TextField("用户名", text: $username, prompt: Text("Jenkins 用户名"))
                        .textContentType(.username)
                        .multilineTextAlignment(.trailing)
                    SecureField("密码", text: $userPassword, prompt: Text("Jenkins 用户名对应的密码"))
                        .textContentType(.password)
                        .multilineTextAlignment(.trailing)
                }

                if let message = localError ?? viewModel.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if viewModel.isSavingServer {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("连接并开始监控")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit || viewModel.isSavingServer)

                    Button("先用样例数据体验界面") {
                        viewModel.enableSampleDataMode()
                    }
                    .disabled(viewModel.isSavingServer)
                } footer: {
                    Text("密码会保存在系统钥匙串中，不会以明文写入磁盘。样例数据仅用于本地预览，不会发起真实网络请求。")
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 560)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !userPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && normalizedURL != nil
    }

    private var normalizedURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    private func save() async {
        localError = nil
        guard let url = normalizedURL else {
            localError = "请输入有效的实例地址。"
            return
        }
        let configuration = ServerConfiguration(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: url,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            userPassword: userPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        _ = await viewModel.saveServer(configuration)
        if viewModel.errorMessage != nil {
            localError = viewModel.errorMessage
        }
    }
}

#Preview {
    OnboardingView(viewModel: MonitoringViewModel(environment: .preview))
        .frame(width: 720, height: 560)
}
