import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: MonitoringViewModel
    @State private var showSettings = false

    var body: some View {
        Group {
            if viewModel.hasConfiguredServer {
                monitoringSplit
            } else {
                OnboardingView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.bootstrap()
        }
    }

    private var monitoringSplit: some View {
        NavigationSplitView {
            JobListView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 360)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    serverFooter
                }
        } content: {
            JobDetailView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 520)
        } detail: {
            buildDetailColumn
        }
        .navigationTitle("Jenkins Monitor")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.refreshAll(force: true) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoadingJobs)
                .keyboardShortcut("r", modifiers: [.command])
                .help("刷新全部实例")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: [.command])
                .help("设置")
            }
        }
    }

    @ViewBuilder
    private var buildDetailColumn: some View {
        if let job = viewModel.selectedJob, let build = viewModel.selectedBuild {
            BuildDetailView(
                job: job,
                build: build,
                buildURL: viewModel.browserURL(for: build.url)
            )
        } else if viewModel.selectedJob != nil {
            EmptyStateView(
                systemImage: "hammer",
                title: "选择一次构建",
                message: "从左侧构建列表中选择一次构建以查看详情。"
            )
        } else {
            EmptyStateView(
                systemImage: "sidebar.left",
                title: "选择一个任务",
                message: "在左侧边栏选择 Jenkins 任务，查看最近构建与详情。"
            )
        }
    }

    private var serverFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(viewModel.servers.count <= 1
                     ? (viewModel.activeServer?.name ?? "实例")
                     : "\(viewModel.servers.count) 个实例")
                    .font(.caption.weight(.semibold))
                StatusBadge(result: viewModel.overallStatus, compact: true)
            }
            if let refreshed = viewModel.lastRefreshedAt {
                Text("上次刷新：\(refreshed.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.bar)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.top, 1)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button {
                viewModel.clearError()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.10))
    }
}

#Preview("已配置") {
    let vm = MonitoringViewModel(environment: .preview)
    return ContentView(viewModel: vm)
        .frame(width: 1100, height: 700)
}

#Preview("引导") {
    ContentView(viewModel: MonitoringViewModel(environment: .live))
        .frame(width: 800, height: 600)
}
