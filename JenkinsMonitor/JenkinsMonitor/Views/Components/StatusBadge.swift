import SwiftUI

struct StatusBadge: View {
    let result: BuildResult
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: result.systemImage)
                .symbolEffect(.pulse, options: .repeating, isActive: result == .inProgress)
            if !compact {
                Text(result.displayName)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(result.tintColor)
        .padding(.horizontal, compact ? 4 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(result.tintColor.opacity(0.12), in: Capsule())
        .accessibilityLabel(result.displayName)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(BuildResult.allCases, id: \.self) { result in
            StatusBadge(result: result)
        }
    }
    .padding()
}
