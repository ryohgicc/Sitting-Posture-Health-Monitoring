import Foundation

/// Only the accepted reference and reminder lines are persisted, never enrollment samples.
public struct PersonalProfile: Codable, Sendable {
    public let version: Int
    public let baseline: PoseMetrics
    public var thresholds: [Issue:Double]
    public init(baseline: PoseMetrics, thresholds: [Issue:Double]) {
        version=1; self.baseline=baseline; self.thresholds=thresholds
    }
    public var validated: PersonalProfile? {
        guard version == 1, baseline.usable,
              Issue.allCases.allSatisfy({ baseline[$0].map { $0.isFinite } ?? true }),
              abs(baseline.headPitch ?? 0) <= .pi/2, abs(baseline.lateral ?? 0) < 2, abs(baseline.shoulderTilt ?? 0) < .pi/2,
              baseline.leftEarGap.map({$0.isFinite && $0 > 0 && $0 < 2}) ?? true,
              baseline.rightEarGap.map({$0.isFinite && $0 > 0 && $0 < 2}) ?? true,
              baseline.headRoll.map({$0.isFinite && abs($0) <= .pi}) ?? true,
              baseline.headScale.map({$0.isFinite && $0 > 0.12 && $0 < 0.9}) ?? true,
              baseline.shoulderSpan.map({$0.isFinite && $0 > 0 && $0 <= 1}) ?? true,
              baseline.headYaw.map({$0.isFinite && abs($0) <= .pi}) ?? true,
              thresholds.allSatisfy({ issue,value in baseline[issue] != nil && value.isFinite && value >= issue.threshold*0.5-1e-12 && value <= issue.threshold*1.8+1e-12 }) else { return nil }
        return self
    }
    public func matches(_ other: PoseMetrics) -> Bool {
        Issue.allCases.allSatisfy { baseline[$0] == other[$0] } &&
        baseline.leftEarGap == other.leftEarGap && baseline.rightEarGap == other.rightEarGap && baseline.headRoll == other.headRoll && baseline.headScale == other.headScale &&
        baseline.shoulderSpan == other.shoulderSpan && baseline.headYaw == other.headYaw
    }
    public func threshold(for issue: Issue, sensitivity: Double = 1) -> Double {
        let multiplier=[0.7,1.0,1.4].contains(sensitivity) ? sensitivity : 1
        let value=thresholds[issue].flatMap { $0.isFinite && $0 >= issue.threshold*0.5 && $0 <= issue.threshold*1.8+1e-12 ? $0 : nil } ?? issue.threshold
        return value*multiplier
    }
}

public enum AdaptationStep: String, Sendable {
    case reference, headDown, leanFirst, leanOther, shoulders, shrug, headForward, experience, review
    public var issue: Issue? {
        switch self {case .headDown:return .headDown; case .leanFirst,.leanOther:return .lean; case .shoulders:return .shoulders; case .shrug:return .shrug; case .headForward:return .headForward; default:return nil}
    }
    public var title: String {
        switch self {
        case .reference:return "1 · 记录舒适参考"
        case .headDown:return "2 · 试一下低头"
        case .leanFirst:return "3 · 头肩向一侧偏移"
        case .leanOther:return "4 · 换另一侧试试"
        case .shoulders:return "5 · 试一下双肩高低差"
        case .shrug:return "6 · 试一下双肩抬高"
        case .headForward:return "7 · 试一下头部前移"
        case .experience:return "8 · 体验提醒和恢复"
        case .review:return "9 · 确认个人提醒线"
        }
    }
    public var instruction: String {
        switch self {
        case .reference:return "背部和双脚有支撑，肩膀放松，自然看屏幕，稳定约10秒。不必挺胸、夹肩。"
        case .headDown:return "先回到参考姿势，再自然低头。在你希望被提醒的位置保持2秒，点记录；不要追求最大幅度。"
        case .leanFirst:return "先回到参考姿势，再向任意一侧自然偏移。在你希望被提醒的位置保持2秒。"
        case .leanOther:return "回到参考姿势，再向刚才相反的一侧偏移，保持2秒。两侧取较早需要提醒的一侧。"
        case .shoulders:return "先回到参考姿势，再轻微改变两肩高低，在希望被提醒的位置保持2秒。不耸肩硬撑。"
        case .shrug:return "先放松双肩并保持头部位置稳定，再轻轻同时抬起双肩。在希望被提醒的位置保持2秒，不用力硬撑；耳朵看不清时可跳过。"
        case .headForward:return "身体与双肩留在原位，保持正面和头部角度稳定，头轻轻向屏幕前移。在希望提醒的位置保持2秒，不用力伸脖子。不便完成可跳过；这只是画面尺度估计。"
        case .experience:return "先回到参考姿势，再自然尝试越过100%提醒线并保持所设时长，看状态何时变为持续偏离；恢复后看3秒恢复过程。这里不发姿态通知。"
        case .review:return "逐项确认提醒线；未完成的项目保留默认线。只有点应用才会替换原来的校准和阈值。"
        }
    }
}

/// Bounded, transient scalar enrollment. No configuration changes until caller accepts profile.
public struct AdaptationSession {
    public private(set) var step: AdaptationStep = .reference
    public private(set) var profile: PersonalProfile?
    public private(set) var readings: [Issue:ThresholdReading] = [:]
    public private(set) var referenceProgress=0.0
    public private(set) var actionProgress=0.0
    public private(set) var message="保持自然舒适姿势；不适时停止，任何动作都可以跳过。"
    public private(set) var notes: [Issue:String] = [:]
    public let preferences: Preferences
    private var calibration=CalibrationAccumulator()
    private var samples: [(Double,PoseMetrics)]=[]
    private var noise: [Issue:Double]=[:]
    private var firstLean: Double?
    private var demo: PostureJudge?
    private var referenceStart: Double?
    public init(preferences: Preferences) {self.preferences=preferences.validated}
    public mutating func update(_ metrics: PoseMetrics?, now: Double) {
        guard now.isFinite else {return}
        if step == .experience || step == .review {
            readings=demo?.update(metrics,now:now).readings ?? [:]; return
        }
        guard let metrics, metrics.usable else {
            samples=[]; actionProgress=0; readings=[:]
            if step == .reference {calibration=CalibrationAccumulator(); referenceProgress=0}
            message="暂时看不清，当前稳定采样已清空。调整入镜后重试，或跳过当前动作。"; return
        }
        if let last=samples.last, now-last.0 > 1 || now <= last.0 {samples=[];actionProgress=0}
        samples.append((now,metrics)); if samples.count > 100 {samples.removeFirst()}
        if step == .reference {
            referenceStart=referenceStart ?? now
            calibration.add(metrics,now:now); referenceProgress=min(1,calibration.duration/10)
            if let b=calibration.result(now:now) {
                profile=PersonalProfile(baseline:b,thresholds:[:])
                for issue in Issue.allCases {
                    let values=samples.compactMap {$0.1.signedDeviation(from:b,issue:issue)}.sorted()
                    if b[issue] != nil, !values.isEmpty {
                        noise[issue]=quantile(values.map {abs($0)}.sorted(),0.95)
                    }
                }
                advance(to:.headDown)
            } else if now-(referenceStart ?? now) > 45 {
                calibration=CalibrationAccumulator(); samples=[]; referenceProgress=0; referenceStart=now
                message="参考采样未成功：保持头肩清晰稳定，再试10秒；也可以取消。"
            }
            return
        }
        guard let issue=step.issue, let baseline=profile?.baseline, let signed=metrics.signedDeviation(from:baseline,issue:issue) else {
            samples=[]; actionProgress=0; readings=[:]; message="此项没有可靠参考或当前不可见，请调整画面或跳过。"; return
        }
        samples.removeAll {now-$0.0 > 3.2}
        actionProgress=min(1,(samples.last!.0-samples.first!.0)/2)
        let delta=issue == .headDown || issue == .shrug || issue == .headForward ? max(0,signed) : abs(signed)
        let line=profile?.threshold(for:issue,sensitivity:preferences.sensitivity) ?? issue.entryThreshold(sensitivity:preferences.sensitivity)
        readings=[issue:ThresholdReading(deviation:delta,threshold:line,phase:delta>line ? .counting : .below,elapsed:0,dwell:preferences.dwell)]
        message=actionProgress >= 1 ? "在你希望被提醒的位置稳定后，点记录。" : "保持当前自然动作约2秒；不需要用力。"
    }
    @discardableResult public mutating func record() -> Bool {
        guard let issue=step.issue, let baseline=profile?.baseline, baseline[issue] != nil, let first=samples.first, let last=samples.last,
              last.0-first.0 >= 2, samples.count >= 8 else {message="有效稳定采样不足2秒，请保持片刻或跳过。";return false}
        let raw=samples.compactMap {$0.1.signedDeviation(from:baseline,issue:issue)}.sorted()
        guard raw.count >= 8, Double(raw.count)/Double(samples.count) >= 0.9 else {message="此项不可见或采样不足，请重试或跳过。";return false}
        let signed=quantile(raw,0.5)
        let delta=issue == .headDown || issue == .shrug || issue == .headForward ? max(0,signed) : abs(signed)
        guard quantile(raw,0.9)-quantile(raw,0.1) < issue.threshold*0.35,
              delta > max(issue.threshold*0.3,(noise[issue] ?? 0)*3) else {message="变化太小、方向不符或仍在移动，无法区分动作与抖动。请自然重试或跳过。";return false}
        if step == .leanFirst {firstLean=signed; advance(to:.leanOther); return true}
        var proposed=delta
        if step == .leanOther {
            guard let firstLean, firstLean*signed < 0 else {message="请先回到参考，再向刚才相反的一侧偏移；也可以跳过左右项目。";return false}
            proposed=min(abs(firstLean),delta)
        }
        profile?.thresholds[issue]=min(issue.threshold*1.4,max(issue.threshold*0.6,proposed/preferences.sensitivity))
        notes[issue]="按自然动作估算（建议范围内），待你体验确认"
        advance(to:step == .headDown ? .leanFirst : step == .leanOther ? .shoulders : step == .shoulders ? .shrug : step == .shrug ? .headForward : .experience)
        return true
    }
    public mutating func skip() {
        guard let issue=step.issue else {return}
        profile?.thresholds[issue]=nil; notes[issue]="未适配 · 保留默认提醒线"
        advance(to:step == .headDown ? .leanFirst : step == .shoulders ? .shrug : step == .shrug ? .headForward : step == .headForward ? .experience : .shoulders)
        if issue == .lean {firstLean=nil}
    }
    public mutating func adjust(_ issue: Issue, factor: Double) {
        guard step == .experience || step == .review, factor.isFinite, factor > 0, profile?.baseline[issue] != nil else {return}
        let current=profile?.thresholds[issue] ?? issue.threshold
        profile?.thresholds[issue]=min(issue.threshold*1.8,max(issue.threshold*0.5,current*factor))
        notes[issue]="手动调整，待确认"; resetDemo()
    }
    public mutating func review() {guard step == .experience else {return};step = .review}
    private mutating func advance(to step: AdaptationStep) {
        self.step=step; samples=[];actionProgress=0;readings=[:]
        message=step.instruction
        if step == .experience {resetDemo()}
    }
    private mutating func resetDemo() {
        readings=[:]
        if let profile {demo=PostureJudge(baseline:profile.baseline,preferences:preferences,profile:profile)}
    }
    private func quantile(_ sorted: [Double], _ fraction:Double) -> Double {
        sorted[Int(Double(sorted.count-1)*fraction)]
    }
}
