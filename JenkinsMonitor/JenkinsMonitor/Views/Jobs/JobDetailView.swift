import SwiftUI

struct JobDetailView: View {
    @Bindable var viewModel: MonitoringViewModel
    @State private var showBuildConfirm = false

    var body: some View {
        Group {
            if let job = viewModel.selectedJob {
                buildList(for: job)
            } else {
                EmptyStateView(
                    systemImage: "sidebar.left",
                    title: "选择一个任务",
                    message: "在左侧边栏选择 Jenkins 任务，查看最近构建与详情。"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedBuildNumber: Binding<Int?> {
        Binding(
            get: { viewModel.selectedBuild?.number },
            set: { viewModel.selectBuild(number: $0) }
        )
    }

    @ViewBuilder
    private func buildList(for job: JenkinsJob) -> some View {
        List(selection: selectedBuildNumber) {
            Section {
                header(for: job)
            }

            Section("最近构建") {
                if viewModel.isLoadingBuilds && viewModel.builds.isEmpty {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("加载中…")
                            .foregroundStyle(.secondary)
                    }
                } else if viewModel.builds.isEmpty {
                    Text("暂无构建记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.builds) { build in
                        HStack {
                            Image(systemName: build.result.systemImage)
                                .foregroundStyle(build.result.tintColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(build.displayName ?? "#\(build.number)")
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                Text(build.formattedTimestamp)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(build.formattedDuration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .tag(build.number)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func header(for job: JenkinsJob) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(job.fullName)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button {
                    showBuildConfirm = true
                } label: {
                    if viewModel.isTriggeringBuild {
                        ProgressView()
                            .controlSize(.small)
                        Text("Build")
                    } else {
                        Label("Build", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isTriggeringBuild)
                .lineLimit(1)

                Link(destination: viewModel.browserURL(for: job.url)) {
                    Label("项目详情", systemImage: "safari")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
            }
            .confirmationDialog("确认开始构建？", isPresented: $showBuildConfirm, titleVisibility: .visible) {
                Button("Build") {
                    Task {
                        await viewModel.triggerDefaultBuild()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将使用默认参数构建「\(job.fullName)」。")
            }
        }
        .padding(.vertical, 4)
    }
}
