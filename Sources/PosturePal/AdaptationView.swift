import SwiftUI
import PostureCore

struct AdaptationView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if let session=model.adaptation {
            GroupBox {
                VStack(alignment:.leading,spacing:14) {
                    HStack {
                        Text(session.step.title).font(.title2.bold())
                        Spacer()
                        Button("取消") {model.cancelAdaptation()}
                    }
                    Text(session.step.instruction)
                    Text("只做轻松自然的动作，不做最大幅度；不适就停止。个人提醒线不代表损伤临界值。")
                        .font(.caption).foregroundStyle(.secondary)
                    if session.step == .reference {
                        ProgressView(value:session.referenceProgress)
                        Text("稳定参考 \(Int(session.referenceProgress*10)) / 10 秒").monospacedDigit()
                    } else if let issue=session.step.issue {
                        ThresholdRow(issue:issue,reading:session.readings[issue],threshold:session.profile?.threshold(for:issue,sensitivity:session.preferences.sensitivity) ?? issue.threshold,unavailable:"此项不可判断")
                        ProgressView(value:session.actionProgress)
                        Text(session.actionProgress >= 1 ? "已取得至少2秒采样，点击后检查动作方向和稳定性。" : "正在采样，保持自然动作至少2秒。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let feedback=session.recordFeedback {
                            Label(feedback,systemImage:"exclamationmark.circle.fill")
                                .font(.callout).foregroundStyle(.orange)
                                .accessibilityLabel(feedback)
                        }
                        HStack {
                            Button(session.recordFeedback == nil ? "记录当前位置并继续" : "重新记录并继续") {model.recordAdaptation()}
                                .buttonStyle(.borderedProminent).disabled(session.actionProgress < 1)
                            Button("跳过此项，保留默认线") {model.skipAdaptation()}
                        }
                        Text("动作页显示即时变化；实际持续计时会在下一步体验。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("试用持续时间：\(Int(session.preferences.dwell))秒 · 恢复需低于提醒线55%并稳定3秒").font(.caption)
                        ForEach(Issue.allCases,id:\.self) {issue in
                            VStack(alignment:.leading,spacing:7) {
                                ThresholdRow(issue:issue,reading:session.readings[issue],threshold:session.profile?.threshold(for:issue,sensitivity:session.preferences.sensitivity) ?? issue.threshold,unavailable:session.profile?.baseline[issue] == nil ? "无可靠参考，不参与判断" : "等待当前读数")
                                Text(session.notes[issue] ?? "未适配 · 保留默认提醒线").font(.caption).foregroundStyle(.secondary)
                                if session.profile?.baseline[issue] != nil {
                                    HStack {
                                        Button("太敏感 · 放宽15%") {model.adjustAdaptation(issue,factor:1.15)}
                                        Button("不够敏感 · 收紧15%") {model.adjustAdaptation(issue,factor:1/1.15)}
                                    }.controlSize(.small)
                                }
                            }
                        }
                        if session.step == .experience {
                            Button("合适，查看并确认") {model.reviewAdaptation()}.buttonStyle(.borderedProminent)
                        } else {
                            Button("确认应用个人参考和提醒线") {model.applyAdaptation()}.buttonStyle(.borderedProminent)
                            Text("仅保存本页最终数值。不保存动作视频或采样历史；姿态系统通知仍保留原来的启用状态。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(session.message).font(.callout).foregroundStyle(.secondary)
                }.padding(8)
            }
        }
    }
}
