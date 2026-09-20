#if DEBUG
import SwiftUI

struct PanelDropTestTarget: View {
    @State private var accepted = false

    var body: some View {
        Text(accepted ? "Drop accepted" : "Panel drop target")
            .font(.headline)
            .padding(.horizontal, 24)
            .frame(width: 260, height: 120)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.blue, style: StrokeStyle(lineWidth: 2, dash: [6])))
            .dropDestination(for: String.self) { values, _ in
                guard !values.isEmpty else { return false }
                accepted = true
                return true
            }
            .accessibilityIdentifier("panel-drop-target")
    }
}
#endif
