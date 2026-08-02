import Foundation

public enum MetricCounter: String, Codable, CaseIterable, Sendable {
    case captureSucceeded
    case captureFailed
    case itemCopied
    case itemOpened
    case itemShared
    case itemDragged
    case itemArchived
    case syncSucceeded
    case syncFailed
    case searchSucceeded
}

public enum MetricDuration: String, Codable, CaseIterable, Sendable {
    case captureDuration
    case searchDuration
}

public struct MetricsSnapshot: Codable, Equatable, Sendable {
    public var counts: [MetricCounter: Int]
    public var durationTotals: [MetricDuration: Double]
    public var durationSamples: [MetricDuration: Int]

    public init(counts: [MetricCounter: Int] = [:], durationTotals: [MetricDuration: Double] = [:], durationSamples: [MetricDuration: Int] = [:]) {
        self.counts = counts
        self.durationTotals = durationTotals
        self.durationSamples = durationSamples
    }
}

public final class OnDeviceMetricsClient {
    private let url: URL
    private var enabled: Bool
    private var value: MetricsSnapshot

    public init(url: URL, enabled: Bool) throws {
        self.url = url
        self.enabled = enabled
        if FileManager.default.fileExists(atPath: url.path) {
            value = try JSONDecoder().decode(MetricsSnapshot.self, from: Data(contentsOf: url))
        } else {
            value = MetricsSnapshot()
        }
    }

    public func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    public func record(_ event: MetricCounter) throws {
        guard enabled else { return }
        value.counts[event, default: 0] += 1
        try persist()
    }

    public func recordDuration(_ metric: MetricDuration, seconds: Double) throws {
        guard enabled, seconds.isFinite, seconds >= 0 else { return }
        value.durationTotals[metric, default: 0] += seconds
        value.durationSamples[metric, default: 0] += 1
        try persist()
    }

    public func snapshot() -> MetricsSnapshot { value }

    private func persist() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
