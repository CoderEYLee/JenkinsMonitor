import SwiftUI

struct JobRowView: View {
    let job: JenkinsJob

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: job.displayStatus.systemImage)
                .foregroundStyle(job.displayStatus.tintColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if job.fullName != job.name {
                    Text(job.fullName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.fullName)，\(job.displayStatus.displayName)")
    }
}
