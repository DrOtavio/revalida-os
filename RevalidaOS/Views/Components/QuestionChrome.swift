import SwiftUI

struct QuestionMetadataHeader: View {
    let question: Question

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(question.displayTopic)
                        .font(.subheadline.bold())
                        .foregroundStyle(.tint)
                    Text(question.displayCategory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(question.sourceEditionLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            if question.isAnnulled {
                Label("ANULADA PELA BANCA", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            }
        }
    }
}

struct QuestionOptionChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let isSelected: Bool
    let isCorrect: Bool
    let isWrong: Bool
    let isAnnulledSelection: Bool

    func body(content: Content) -> some View {
        content
            .background(fillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            }
    }

    private var fillColor: Color {
        if isCorrect { return Color.green.opacity(colorScheme == .dark ? 0.13 : 0.10) }
        if isWrong { return Color.red.opacity(colorScheme == .dark ? 0.13 : 0.08) }
        if isAnnulledSelection { return Color.orange.opacity(colorScheme == .dark ? 0.13 : 0.09) }
        if isSelected { return Color.accentColor.opacity(colorScheme == .dark ? 0.14 : 0.08) }
        return colorScheme == .dark ? Color.white.opacity(0.025) : Color.secondary.opacity(0.05)
    }

    private var borderColor: Color {
        if isCorrect { return .green }
        if isWrong { return .red }
        if isAnnulledSelection { return .orange }
        if isSelected { return .accentColor }
        return colorScheme == .dark ? Color.blue.opacity(0.72) : Color.clear
    }

    private var borderWidth: CGFloat {
        if isCorrect || isWrong || isAnnulledSelection || isSelected { return 1.7 }
        return colorScheme == .dark ? 1.0 : 0
    }
}

extension View {
    func questionOptionChrome(
        selected: Bool = false,
        correct: Bool = false,
        wrong: Bool = false,
        annulledSelection: Bool = false
    ) -> some View {
        modifier(QuestionOptionChrome(
            isSelected: selected,
            isCorrect: correct,
            isWrong: wrong,
            isAnnulledSelection: annulledSelection
        ))
    }
}
