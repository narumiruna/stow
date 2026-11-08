import CoreGraphics
import Foundation
import ImageIO

/// Reads image dimensions without decoding pixels or retaining the image.
enum ItemCardMediaMetadata {
    static func aspectRatio(in data: Data) -> CGFloat? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let ratio = (5...8).contains(orientation) ? height / width : width / height
        return CGFloat(min(1.8, max(0.75, ratio)))
    }
}
