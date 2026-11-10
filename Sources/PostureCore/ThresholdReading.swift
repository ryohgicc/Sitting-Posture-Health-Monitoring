import Foundation

public enum ThresholdPhase: Sendable { case below, approaching, counting, active, recovering, muted }

/// State read directly from the judge;100% is the entry line, not a health score.
public struct ThresholdReading: Sendable {
    public let deviation: Double
    public let threshold: Double
    public let phase: ThresholdPhase
    public let elapsed: Double
    public let dwell: Double
    public var ratio: Double {deviation/threshold}
    public var formattedRatio: String {
        let percent=ratio*100
        if percent < 100, percent >= 99.5 {return "<100%"}
        if percent > 100, percent <= 100.5 {return ">100%"}
        if percent < 80, percent >= 79.5 {return "<80%"}
        return String(format:"%.0f%%",percent)
    }
    public var recoveryThreshold: Double {threshold*0.55}
    public var label: String {
        switch phase {
        case .below: return "未超线"
        case .approaching: return "接近提醒线"
        case .counting: return String(format:"超线 %.0f / %.0f 秒",floor(elapsed),dwell)
        case .active: return "持续偏离"
        case .recovering: return String(format:"恢复中 %.0f / 3 秒",floor(elapsed))
        case .muted: return "提醒已静默"
        }
    }
}

extension Issue {
    public func entryThreshold(sensitivity: Double) -> Double {threshold*sensitivity}
    public func displayValue(_ value:Double) -> Double {self == .lean || self == .shrug || self == .headForward ? value*100 : value*180 / .pi}
    public func formatted(_ value:Double) -> String {
        if self == .headForward {return String(format:"%.1f%% 头肩尺度增幅",displayValue(value))}
        return String(format:self == .lean || self == .shrug ? "%.1f%% 肩宽" : "%.1f°",displayValue(value))
    }
    public var explanation: String {
        switch self {
        case .headDown: return "面部向下俯仰相对参考的增加；不是颈椎角度。"
        case .lean: return "鼻子相对双肩中点的偏移比例变化；不是躯干角度。"
        case .shoulders: return "双肩连线倾斜相对参考的变化，按角度显示；不判断双侧耸肩或圆肩。"
        case .headForward: return "头部相对双肩的画面尺度比相对参考的增幅；正面估计，不能测颈椎前倾角度，仍可能混淆身体移动。"
        case .shrug: return "两侧肩耳距离相对参考都缩短时取较小变化，按双肩横向间距比例显示；头部位移也可能影响估计。"
        }
    }
    public var actionHint: String {
        switch self {
        case .headDown: return "可放松抬头，检查屏幕是否过低，或换个姿势。"
        case .lean: return "可回到舒适的居中位置，或起身活动。"
        case .shoulders: return "可放松双肩，检查两侧扶手和手臂支撑是否合适。"
        case .headForward: return "可让头部回到舒适位置，检查屏幕距离和文字大小，避免用力收下巴。"
        case .shrug: return "可放松双肩，检查桌面、扶手高度与前臂支撑。"
        }
    }
}
