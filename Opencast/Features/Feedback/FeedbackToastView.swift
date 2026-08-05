import SwiftUI

enum FeedbackToastTone: Equatable, Sendable {
    case success
    case failure
    case neutral

    init(style: String?) {
        switch style?.lowercased() {
        case "failure", "error", "destructive", "warning": self = .failure
        case "success", "animated": self = .success
        default: self = .success
        }
    }

    var accent: Color {
        switch self {
        case .success: Theme.Colors.feedbackAccent
        case .failure: Theme.Colors.destructive
        case .neutral: Theme.Colors.systemAccent
        }
    }
}

struct FeedbackToastView: View {
    let title: String?
    let message: String
    let tone: FeedbackToastTone
    var compact = false

    private var shape: Capsule { Capsule() }

    var body: some View {
        VStack(spacing: compact ? Theme.Spacing.xxs : Theme.Spacing.sm) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(compact ? Theme.Typography.calloutMedium : Theme.Typography.feedbackToastTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
            }
            Text(message)
                .font(compact ? Theme.Typography.caption : Theme.Typography.feedbackToast)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, compact ? Theme.Spacing.lg : Theme.Spacing.feedbackToastHorizontal)
        .padding(.vertical, compact ? Theme.Spacing.sm : Theme.Spacing.feedbackToastVertical)
        .fixedSize(horizontal: !compact, vertical: false)
        .frame(
            minWidth: compact ? nil : Theme.Size.menuButton,
            maxWidth: compact ? nil : Theme.Size.feedbackToastMaxWidth,
            minHeight: compact ? nil : Theme.Size.menuButton
        )
        .background {
            shape
                .fill(Theme.Colors.feedbackShade)
                .overlay {
                    shape.fill(tone.accent.opacity(compact ? 0.10 : 0.14))
                }
        }
        .overlay {
            shape.strokeBorder(Theme.Colors.feedbackStroke, lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(compact ? 0.14 : 0.24),
            radius: compact ? 6 : 10,
            y: compact ? 3 : 5
        )
        .accessibilityElement(children: .combine)
    }
}
