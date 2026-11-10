import Foundation

public struct Preferences: Codable, Sendable {
    public var dwell: Double
    public var cooldown: Double
    public var sensitivity: Double
    public var activityInterval: Double
    public init(dwell: Double = 5, cooldown: Double = 600, sensitivity: Double = 1, activityInterval: Double = 2700) {
        self.dwell = dwell.isFinite ? min(120,max(1,dwell.rounded())) : 5
        self.cooldown = [300.0,600,1200].contains(cooldown) ? cooldown : 600
        self.sensitivity = [0.7,1.0,1.4].contains(sensitivity) ? sensitivity : 1
        self.activityInterval = [1800.0,2700,3600].contains(activityInterval) ? activityInterval : 2700
    }
    public var validated: Preferences { Preferences(dwell: dwell, cooldown: cooldown, sensitivity: sensitivity, activityInterval: activityInterval) }
}

private struct Tracker {
    var filtered: Double?
    var badSince: Double?
    var goodSince: Double?
    var active = false
}

public struct Verdict {
    public var active: Set<Issue>
    public var alerts: Set<Issue>
    public var deviations: [Issue: Double]
    public var readings: [Issue:ThresholdReading]
}

public struct PostureJudge {
    public var baseline: PoseMetrics
    public var preferences: Preferences
    public var enabled = Set(Issue.allCases)
    private var trackers: [Issue:Tracker] = [:]
    private var lastFrame: Double?
    private var lastAlerts: [Issue:Double] = [:]
    private var lastAnyAlert: Double?
    private let smoothing: Bool
    public init(baseline: PoseMetrics, preferences: Preferences = Preferences(), smoothing: Bool = true) {
        self.baseline = baseline; self.preferences = preferences.validated; self.smoothing = smoothing
    }
    public mutating func resetPending() { trackers.removeAll(); lastFrame = nil }
    public mutating func update(_ metrics: PoseMetrics?, now: Double, muted: Bool = false) -> Verdict {
        let dt = lastFrame.map { now-$0 } ?? 0
        if dt > 2.5 || dt < 0 { trackers.removeAll() }
        lastFrame = now
        var active = Set<Issue>(), candidates = Set<Issue>(), deviations: [Issue:Double] = [:]
        var readings: [Issue:ThresholdReading] = [:]
        for issue in Issue.allCases {
            guard enabled.contains(issue), let raw = metrics?[issue], let base = baseline[issue], raw.isFinite, base.isFinite else {
                trackers[issue] = nil; continue
            }
            var t = trackers[issue] ?? Tracker()
            // Vision reports positive pitch for nodding down; looking up must not count as head-down.
            let deviation = issue == .headDown ? max(0, raw-base) : abs(raw-base)
            let alpha = smoothing ? 1-exp(-max(0,dt)/0.8) : 1
            t.filtered = t.filtered.map { $0 + alpha*(deviation-$0) } ?? deviation
            deviations[issue] = t.filtered
            let entry = issue.entryThreshold(sensitivity:preferences.sensitivity)
            let threshold = entry * (t.active ? 0.55 : 1)
            if muted { t.badSince = nil; t.goodSince = nil; t.active = false }
            else if (t.filtered ?? 0) > threshold {
                t.goodSince = nil; t.badSince = t.badSince ?? now
                if now-(t.badSince ?? now) >= preferences.dwell { t.active = true }
            } else {
                t.badSince = nil; t.goodSince = t.goodSince ?? now
                if now-(t.goodSince ?? now) >= 3 { t.active = false }
            }
            if t.active {
                active.insert(issue)
                if now-(lastAlerts[issue] ?? -.infinity) >= preferences.cooldown { candidates.insert(issue) }
            }
            let phase: ThresholdPhase
            let elapsed: Double
            if muted {phase = .muted;elapsed=0}
            else if t.active, let since=t.goodSince {phase = .recovering;elapsed=max(0,now-since)}
            else if t.active {phase = .active;elapsed=t.badSince.map {max(0,now-$0)} ?? 0}
            else if let since=t.badSince {phase = .counting;elapsed=max(0,now-since)}
            else {phase = (t.filtered ?? 0)/entry >= 0.8-1e-12 ? .approaching : .below;elapsed=0}
            readings[issue]=ThresholdReading(deviation:t.filtered ?? 0,threshold:entry,phase:phase,elapsed:elapsed,dwell:preferences.dwell)
            trackers[issue] = t
        }
        if muted || now-(lastAnyAlert ?? -.infinity) < 60 { candidates.removeAll() }
        if !candidates.isEmpty {
            lastAnyAlert = now
            for i in candidates { lastAlerts[i] = now }
        }
        return Verdict(active: active, alerts: candidates, deviations: deviations, readings: readings)
    }
}
