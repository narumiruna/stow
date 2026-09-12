import AppKit
import SwiftUI

/// Semantic surfaces shared by the macOS Library, Quick Panel, and Settings.
enum MacVisualStyle {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let cornerRadius: CGFloat = 14
}

struct MacSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(MacVisualStyle.surface, in: RoundedRectangle(cornerRadius: MacVisualStyle.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: MacVisualStyle.cornerRadius)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.08))
                    .allowsHitTesting(false)
            }
    }
}

struct MacSymbolTile: View {
    let symbol: String
    var tint: Color = .accentColor
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

struct MacEmptyState<Actions: View>: View {
    let title: String
    let symbol: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 16) {
            MacSymbolTile(symbol: symbol, size: 64)
                .padding(.bottom, 4)
            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            actions()
                .controlSize(.large)
        }
        .frame(maxWidth: 300)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MacShortcutHint: View {
    let keys: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(MacVisualStyle.surface, in: RoundedRectangle(cornerRadius: 5))
            Text(title).font(.caption)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
