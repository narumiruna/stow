import SwiftUI

struct MasonryLayout: Layout {
    var columnCount = 2
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? 320, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrangement(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, arrangement.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> MasonryArrangement {
        let columnWidth = MasonryArrangement.columnWidth(width: width, columns: columnCount, spacing: spacing)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
        return MasonryArrangement(width: width, columns: columnCount, spacing: spacing, heights: heights)
    }
}

struct MasonryArrangement {
    let frames: [CGRect]
    let size: CGSize

    static func columnWidth(width: CGFloat, columns: Int, spacing: CGFloat) -> CGFloat {
        let columns = max(1, columns)
        return max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
    }

    init(width: CGFloat, columns: Int, spacing: CGFloat, heights: [CGFloat]) {
        let columns = max(1, columns)
        let columnWidth = Self.columnWidth(width: width, columns: columns, spacing: spacing)
        var bottoms = Array(repeating: CGFloat.zero, count: columns)
        var frames: [CGRect] = []
        for height in heights {
            let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            let frame = CGRect(
                x: CGFloat(column) * (columnWidth + spacing),
                y: bottoms[column],
                width: columnWidth,
                height: max(0, height)
            )
            frames.append(frame)
            bottoms[column] = frame.maxY + spacing
        }
        self.frames = frames
        size = CGSize(width: max(0, width), height: max(0, (bottoms.max() ?? 0) - (heights.isEmpty ? 0 : spacing)))
    }
}
