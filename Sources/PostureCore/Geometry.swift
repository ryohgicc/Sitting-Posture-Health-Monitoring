import Foundation

public struct Point2: Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct FrameGeometry: Sendable {
    public let leftShoulder: Point2
    public let rightShoulder: Point2
    public let head: Point2?
    public init(leftShoulder: Point2, rightShoulder: Point2, head: Point2?) {
        self.leftShoulder = leftShoulder; self.rightShoulder = rightShoulder; self.head = head
    }
    private var width: Double { hypot(rightShoulder.x-leftShoulder.x, rightShoulder.y-leftShoulder.y) }
    private var valid: Bool { width.isFinite && width > 30 && abs(rightShoulder.x-leftShoulder.x) / width > 0.7 }
    public var lateral: Double? {
        guard valid, let head, head.x.isFinite, head.y.isFinite else { return nil }
        return (head.x - (leftShoulder.x+rightShoulder.x)/2)/width
    }
    public var shoulderTilt: Double? {
        guard valid else { return nil }
        // Use image-left to image-right so anatomical naming does not change the angle by pi.
        let a = leftShoulder.x < rightShoulder.x ? leftShoulder : rightShoulder
        let b = leftShoulder.x < rightShoulder.x ? rightShoulder : leftShoulder
        return atan2(b.y-a.y, b.x-a.x)
    }
}

public struct PoseMetrics: Codable, Sendable {
    public var headPitch: Double?
    public var lateral: Double?
    public var shoulderTilt: Double?
    public var leftEarGap: Double?
    public var rightEarGap: Double?
    public var headRoll: Double?
    public init(headPitch: Double?, lateral: Double?, shoulderTilt: Double?, leftEarGap: Double? = nil, rightEarGap: Double? = nil, headRoll: Double? = nil) {
        self.headPitch = headPitch.flatMap { $0.isFinite ? $0 : nil }
        self.lateral = lateral.flatMap { $0.isFinite ? $0 : nil }
        self.shoulderTilt = shoulderTilt.flatMap { $0.isFinite ? $0 : nil }
        self.leftEarGap = leftEarGap.flatMap { $0.isFinite && $0 > 0 && $0 < 2 ? $0 : nil }
        self.rightEarGap = rightEarGap.flatMap { $0.isFinite && $0 > 0 && $0 < 2 ? $0 : nil }
        self.headRoll = headRoll.flatMap { $0.isFinite ? $0 : nil }
    }
    public subscript(_ issue: Issue) -> Double? {
        switch issue { case .headDown: return headPitch; case .lean: return lateral; case .shoulders: return shoulderTilt
        case .shrug:
            guard let leftEarGap, let rightEarGap, leftEarGap.isFinite, rightEarGap.isFinite,
                  leftEarGap > 0, rightEarGap > 0, leftEarGap < 2, rightEarGap < 2,
                  headPitch?.isFinite == true, headRoll?.isFinite == true else {return nil}
            return (leftEarGap+rightEarGap)/2
        }
    }
    /// Signed change in the direction being enrolled. Bilateral elevation requires both gaps to shrink.
    public func signedDeviation(from baseline: PoseMetrics, issue: Issue) -> Double? {
        guard let raw=self[issue], let base=baseline[issue], raw.isFinite, base.isFinite else {return nil}
        guard issue == .shrug else {return raw-base}
        guard let pitch=headPitch, let basePitch=baseline.headPitch,
              let roll=headRoll, let baseRoll=baseline.headRoll,
              abs(pitch-basePitch) < 0.12, abs(roll-baseRoll) < 0.12,
              let left=leftEarGap, let right=rightEarGap,
              let baseLeft=baseline.leftEarGap, let baseRight=baseline.rightEarGap else {return nil}
        return min(baseLeft-left,baseRight-right)
    }
    public var complete: Bool { Issue.allCases.allSatisfy { self[$0]?.isFinite == true } }
    public var usable: Bool { Issue.allCases.contains { self[$0]?.isFinite == true } }
}

public enum Issue: String, CaseIterable, Codable, Sendable {
    case headDown, lean, shoulders, shrug
    public var title: String {
        switch self { case .headDown: return "头部俯仰"; case .lean: return "头肩横向偏移"; case .shoulders: return "双肩高低差"; case .shrug: return "双肩抬高" }
    }
    public var threshold: Double {
        switch self { case .headDown: return 0.20; case .lean: return 0.18; case .shoulders: return 0.14; case .shrug: return 0.08 }
    }
}

public struct CalibrationAccumulator {
    private var samples: [(Double, PoseMetrics)] = []
    public init() {}
    public mutating func add(_ m: PoseMetrics, now: Double) {
        guard now.isFinite, m.usable else { samples.removeAll(); return }
        if let last = samples.last, now-last.0 > 1 || now <= last.0 { samples.removeAll() }
        samples.append((now,m))
        if samples.count > 100 { samples.removeFirst() }
    }
    public var duration: Double { guard let a = samples.first, let b = samples.last else { return 0 }; return b.0-a.0 }
    public func result(now: Double) -> PoseMetrics? {
        guard samples.count >= 30, duration >= 10, let last = samples.last, now-last.0 <= 1 else { return nil }
        var values: [Issue: Double] = [:]
        for issue in Issue.allCases {
            let a = samples.compactMap { $0.1[issue] }.filter(\.isFinite).sorted()
            guard a.count >= 30, Double(a.count)/Double(samples.count) >= 0.9 else { continue }
            let median = a[a.count/2]
            guard a[Int(Double(a.count-1)*0.9)] - a[Int(Double(a.count-1)*0.1)] < issue.threshold * 0.6 else { continue }
            values[issue] = median
        }
        guard !values.isEmpty else { return nil }
        func stable(_ get: (PoseMetrics) -> Double?, tolerance: Double) -> Double? {
            let sorted=samples.compactMap {get($0.1)}.filter(\.isFinite).sorted()
            guard sorted.count >= 30, Double(sorted.count)/Double(samples.count) >= 0.9,
                  sorted[Int(Double(sorted.count-1)*0.9)]-sorted[Int(Double(sorted.count-1)*0.1)] < tolerance else {return nil}
            return sorted[sorted.count/2]
        }
        let left=stable({$0.leftEarGap},tolerance:Issue.shrug.threshold*0.6)
        let right=stable({$0.rightEarGap},tolerance:Issue.shrug.threshold*0.6)
        let roll=stable({$0.headRoll},tolerance:0.08)
        let hasShrug=values[.shrug] != nil && left != nil && right != nil && roll != nil && values[.headDown] != nil
        return PoseMetrics(headPitch: values[.headDown], lateral: values[.lean], shoulderTilt: values[.shoulders],leftEarGap:hasShrug ? left : nil,rightEarGap:hasShrug ? right : nil,headRoll:roll)
    }
}

/// Rejects large frame-to-frame scale changes until the new framing settles.
public struct ScaleContinuity {
    private var lastWidth: Double?
    private var settleUntil: Double?
    public init() {}
    public mutating func accept(width: Double, now: Double) -> Bool {
        guard width.isFinite, width > 30 else { lastWidth = nil; settleUntil = nil; return false }
        defer { lastWidth = width }
        if let old = lastWidth, abs(width/old-1) > 0.25 { settleUntil = now+3; return false }
        if let until = settleUntil, now < until { return false }
        settleUntil = nil
        return true
    }
}
