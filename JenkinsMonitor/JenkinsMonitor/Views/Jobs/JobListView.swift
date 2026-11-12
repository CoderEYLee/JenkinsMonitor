import SwiftUI

struct JobListView: View {
    @Bindable var viewModel: MonitoringViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        List(selection: selectedJobID) {
            listContent
        }
        .listStyle(.sidebar)
        .searchable(text: $viewModel.searchText, placement: .sidebar, prompt: "搜索项目")
    }

    private var selectedJobID: Binding<String?> {
        Binding(
            get: { viewModel.selectedMonitoredJobID },
            set: { viewModel.selectJob(id: $0) }
        )
    }

    @ViewBuilder
    private var listContent: some View {
        if isInitialLoading {
            loadingRow(title: "正在加载项目…")
        } else if viewModel.instanceJobGroups.isEmpty {
            emptyState
        } else {
            instanceSections
        }
    }

    private var isInitialLoading: Bool {
        viewModel.isLoadingJobs
            && viewModel.allMonitoredJobs.isEmpty
            && viewModel.instanceErrors.isEmpty
    }

    @ViewBuilder
    private var instanceSections: some View {
        ForEach(viewModel.instanceJobGroups) { group in
            Section(group.server.name) {
                sectionContent(for: group)
            }
        }
    }

    @ViewBuilder
    private func sectionContent(for group: InstanceJobGroup) -> some View {
        if group.isLoading && group.jobs.isEmpty {
            loadingRow(title: "正在加载…")
        } else if group.jobs.isEmpty {
            Text(group.errorMessage ?? "暂无项目")
                .foregroundStyle(group.errorMessage == nil ? Color.secondary : Color.red)
        } else {
            ForEach(group.jobs) { item in
                JobRowView(job: item.job)
                    .tag(item.id)
                    .contextMenu {
                        Button("项目详情") {
                            openURL(jobHomeURL(for: item.job))
                        }
                    }
            }
        }
    }

    private func loadingRow(title: String) -> some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }


    private func jobHomeURL(for job: JenkinsJob) -> URL {
        viewModel.browserURL(for: job.url)
    }

    private var emptyState: some View {
        let message = viewModel.searchText.isEmpty
            ? "还没有可显示的项目，或尚未刷新。"
            : "没有匹配“\(viewModel.searchText)”的项目。"
        return ContentUnavailableView(
            "没有项目",
            systemImage: "tray",
            description: Text(message)
        )
    }
}
