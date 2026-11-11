import Foundation

/// Fractions describe a named phase with a known denominator, never a whole-disk estimate.
public struct ScanProgress {
    public var phase: String
    public var completed: Double
    public var total: Double?
    public var unit: String
    public var path: String
    public var filesInspected: Int?
    public init(_ phase: String, completed: Double = 0, total: Double? = nil, unit: String = "items", path: String = "", filesInspected: Int? = nil) {
        self.phase = phase; self.completed = completed; self.total = total; self.unit = unit; self.path = path; self.filesInspected = filesInspected
    }
    public var fraction: Double? {
        guard let total, total > 0, total.isFinite, completed.isFinite else { return nil }
        return min(1, max(0, completed / total))
    }
    public var label: String {
        if let fraction { return "\(phase) · \(Int(fraction * 100))%" }
        return phase
    }
    public var detail: String {
        var detail = total.map { "\(completed.formatted(.number.precision(.fractionLength(0)))) / \($0.formatted(.number.precision(.fractionLength(0)))) \(unit)" } ?? (completed > 0 ? "\(completed.formatted(.number.precision(.fractionLength(0)))) \(unit) discovered" : "Finding the work to scan…")
        if let filesInspected { detail += " · \(filesInspected.formatted()) entries inspected in current item" }
        return detail
    }
}

public enum StorageThresholdUnit: String, Codable, CaseIterable, Identifiable {
    case percent = "% free", gigabytes = "GB free"
    public var id: String { rawValue }
}
public struct MenuBarStorageSettings: Codable, Equatable {
    public var enabled = true
    public var unit: StorageThresholdUnit = .percent
    public var threshold: Double = 10
    public init() {}
    public func isLow(total: Int64, free: Int64) -> Bool {
        guard enabled, total > 0, free >= 0, free <= total, threshold.isFinite, threshold > 0 else { return false }
        switch unit {
        case .percent: return Double(free) / Double(total) * 100 <= min(100, threshold)
        case .gigabytes: return Double(free) / 1_000_000_000 <= threshold
        }
    }
    public static func percentageLeft(total: Int64, free: Int64) -> String? {
        guard total > 0, free >= 0, free <= total else { return nil }
        let percentage = Double(free) / Double(total) * 100
        if percentage > 0 && percentage < 1 { return "<1% left" }
        return "\(Int(percentage.rounded(.down)))% left"
    }
}
