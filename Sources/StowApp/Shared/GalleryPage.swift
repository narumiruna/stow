/// A replacement page bounds card creation, attachment queries, and masonry measurements.
struct GalleryPage {
    static let capacity = 40

    let index: Int
    let count: Int
    let range: Range<Int>

    init(itemCount: Int, index: Int) {
        let itemCount = max(0, itemCount)
        count = itemCount == 0 ? 1 : (itemCount - 1) / Self.capacity + 1
        self.index = min(max(0, index), count - 1)
        let start = self.index * Self.capacity
        range = start..<(start + min(Self.capacity, itemCount - start))
    }

    var hasPrevious: Bool { index > 0 }
    var hasNext: Bool { index < count - 1 }
}
