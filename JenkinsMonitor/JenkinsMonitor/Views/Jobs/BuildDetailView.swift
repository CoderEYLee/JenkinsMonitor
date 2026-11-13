import SwiftUI

struct BuildDetailView: View {
    let job: JenkinsJob
    let build: JenkinsBuild
    let buildURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(build.displayName ?? "#\(build.number)")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                StatusBadge(result: build.result)
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    labeledValue("状态", build.result.displayName)
                    labeledValue("构建号", "#\(build.number)")
                }
                GridRow {
                    labeledValue("开始时间", build.formattedTimestamp)
                    labeledValue("耗时", build.formattedDuration)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))

            Link(destination: buildURL) {
                Label("构建详情", systemImage: "safari")
                    .lineLimit(1)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func labeledValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
                .lineLimit(2)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}
