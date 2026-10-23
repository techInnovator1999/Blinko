import SwiftUI

// Shared pieces for Home widgets: the card every non-bare widget sits in, its caption, and
// a hint shown when a widget's feature is off.

enum WidgetMetrics {
    /// Cards line up with the player artwork and the mirror: 8 pt down, 112 pt tall.
    static let cardHeight: CGFloat = 112
    static let cardTop: CGFloat = 8
    static let cardRadius: CGFloat = 16
    static let cardPadding: CGFloat = 10
}

/// Rounded card on the island, padded, content top-leading.
struct WidgetCard<Content: View>: View {
    var padding: CGFloat = WidgetMetrics.cardPadding
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetMetrics.cardRadius, style: .continuous)
        // min 0: the card always takes its column's size, content never stretches it.
        content
            .padding(padding)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill(Color.fillSubtle))
            .clipShape(shape)
    }
}

/// Small uppercase caption at the top of a card ("CPU", "SHELF").
struct WidgetCaption: View {
    let title: LocalizedStringKey
    var tint: Color = .tertiaryText
    var trailing: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(title).textCase(.uppercase)
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(tint)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let trailing {
                Text(verbatim: trailing)
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.tertiaryText)
                    .lineLimit(1)
            }
        }
    }
}

/// Centered symbol + message (+ optional action) for a widget whose feature is off or empty.
struct WidgetHint: View {
    let symbol: String
    let title: LocalizedStringKey
    var action: LocalizedStringKey?
    var perform: (() -> Void)?

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.secondaryText)
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let action, let perform {
                Button(action: perform) {
                    Text(action)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                        .padding(.horizontal, 9)
                        .frame(height: 20)
                        .background(Capsule().fill(Color.fillHover))
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// Frames a card widget in its column: full column width, card height, aligned with the artwork.
    func widgetCardFrame() -> some View {
        frame(maxWidth: .infinity)
            .frame(height: WidgetMetrics.cardHeight)
            .padding(.top, WidgetMetrics.cardTop)
    }
}

@MainActor
enum WidgetActions {
    /// Opens a Settings pane from the island (closing the island first, like the header gear).
    static func openSettings(_ pane: SettingsPane, vm: NotchViewModel) {
        vm.close()
        SettingsWindowController.shared.show(pane: pane)
    }
}
