import SwiftUI
import AVFoundation
import PostureCore

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var privacyPrompt = false
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection:$selectedTab) {
            dashboard.tabItem { Label("状态与校准", systemImage: "figure.seated.side") }.tag(0)
            settings.tabItem { Label("设置", systemImage: "slider.horizontal.3") }.tag(1)
            validation.tabItem { Label("验证与限制", systemImage: "checkmark.shield") }.tag(2)
        }
        .padding(20).frame(minWidth: 720, minHeight: 700)
        .alert("开启摄像头监测？", isPresented: $privacyPrompt) {
            Button("取消", role: .cancel) {}
            Button("开启摄像头") { model.start() }
        } message: { Text("画面仅在本机内存中处理，不录像、不保存照片、不上传。关闭窗口后仍继续监测，菜单栏可随时停止。摄像头工作时系统指示灯会亮。") }
    }
    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("坐姿搭子").font(.largeTitle.bold())
                        Text("\(model.captureState) · 本机处理 · 无声提醒").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.requested {
                        Button("停止检测", role: .destructive) { model.stop() }
                    } else { Button("开启监测") { privacyPrompt = true }.buttonStyle(.borderedProminent) }
                }
                if model.validationMode {
                    Label("当前为验证模式：显示姿态事件，暂不发送姿态纠正通知。", systemImage: "flask").font(.callout).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                if model.capturing && model.showPreview {
                    ZStack {
                        Color.black
                        if let image = model.previewImage {
                            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit).scaleEffect(x: -1, y: 1)
                        } else {
                            Text("正在准备预览…").foregroundStyle(.white)
                        }
                        if model.showOverlay {
                            Canvas { ctx, size in
                                let aspect=model.sourceAspect
                                func mapped(_ pt: Point2) -> CGPoint {
                                    let m=PreviewGeometry.map(pt,sourceAspect:aspect,width:size.width,height:size.height)
                                    return CGPoint(x:m.x,y:m.y)
                                }
                                let p = model.points.map { mapped(Point2(x:$0.x,y:$0.y)) }
                                if let box=model.subjectBox {
                                    let a=mapped(Point2(x:box.x,y:box.y+box.height)), b=mapped(Point2(x:box.x+box.width,y:box.y))
                                    let rect=CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y))
                                    ctx.stroke(Path(roundedRect:rect,cornerRadius:6),with:.color(.mint),lineWidth:2)
                                }
                                if p.count == 1 { ctx.fill(Path(ellipseIn:CGRect(x:p[0].x-4,y:p[0].y-4,width:8,height:8)),with:.color(.mint)) }
                                if p.count == 3 {
                                    var path = Path(); path.move(to: p[0]); path.addLine(to: p[1]); path.move(to: CGPoint(x: (p[0].x+p[1].x)/2, y: (p[0].y+p[1].y)/2)); path.addLine(to: p[2])
                                    ctx.stroke(path, with: .color(.mint), lineWidth: 3)
                                    for pt in p { ctx.fill(Path(ellipseIn: CGRect(x: pt.x-4,y: pt.y-4,width: 8,height: 8)), with: .color(.white)) }
                                }
                            }.allowsHitTesting(false)
                        }
                        GeometryReader { proxy in
                            Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { value in
                                if let p=PreviewGeometry.unmap(Point2(x:value.location.x,y:value.location.y),sourceAspect:model.sourceAspect,width:proxy.size.width,height:proxy.size.height) { model.relock(pick:p) }
                            })
                        }
                    }.aspectRatio(4/3, contentMode: .fit).frame(maxHeight: 290).clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 8) { Image(systemName: "video.slash").font(.system(size: 36)); Text(model.capturing ? "预览已隐藏，摄像头仍工作" : "摄像头未开启") }.foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 150).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }
                HStack { Toggle("显示预览", isOn: $model.showPreview); Toggle("关键点叠加", isOn: $model.showOverlay).help("绿线是经防抖处理的估计位置，不是肩部精确测量；轻微晃动不代表姿势异常。"); Spacer(); Button(model.calibrating ? "校准中…" : "校准 / 重新校准") { model.beginCalibration() }.disabled(!model.capturing || model.calibrating) }
                HStack {
                    Button("重新锁定我") { model.relock() }.disabled(!model.capturing)
                    Text("默认锁定前景使用者；选错时点预览中自己的脸。重新锁定后需校准。").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("背景模糊（应用内）", isOn: $model.backgroundBlur)
                    .help("使用系统摄像头效果时可关闭，减少应用分割开销；选择会自动保存。")
                Text((model.backgroundBlur ? "应用背景模糊已开启。" + (model.capturing && model.showPreview && !model.previewTargetVisible ? "尚未确认人物轮廓，预览全幅模糊或留空。" : "") : "应用背景模糊已关闭，显示摄像头画面；可使用系统摄像头效果。") + "不录像、不保存。")
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.reason).foregroundStyle(.secondary).textSelection(.enabled)
                if model.adaptation != nil {
                    AdaptationView(model:model)
                } else {
                    GroupBox(model.hasPersonalAdaptation ? "个人适配" : "首次使用 · 找到自己的提醒边界") {
                        HStack {
                            Text("记录舒适参考，再试几个自然动作；明确确认后才应用。约1–2分钟，随时可取消。")
                                .font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("开始个人适配") {model.startAdaptation()}.disabled(!model.capturing || model.calibrating)
                        }.padding(6)
                    }
                }
                if !model.adaptationMessage.isEmpty {Text(model.adaptationMessage).font(.callout).foregroundStyle(.secondary)}
                if model.calibrating { ProgressView(value: model.calibrationProgress); Text("保持舒适姿势，直到稳定采样满10秒。调整屏幕后需重校准。").font(.caption) }
                if model.adaptation == nil { GroupBox("提醒边界 · 相对个人参考姿势") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("100% 为提醒线；超过后持续 \(Int(model.preferences.dwell)) 秒才形成事件。80% 起标为接近，仅用于提示。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(Issue.allCases, id: \.self) { issue in
                            ThresholdRow(issue:issue,reading:model.readings[issue],threshold:model.effectiveThreshold(issue),unavailable: !model.enabled.contains(issue) ? "已关闭" : model.calibrating ? "校准中" : model.baseline?[issue] == nil ? (issue == .shrug ? "需双耳入镜后重新校准" : "等待校准") : "不可判断")
                        }
                        Text("显示的是估计变化和工程提醒线，不是健康评分或损伤临界值。恢复到提醒线的55%以内并稳定3秒后，偏离事件才会消退，避免边界附近反复跳变。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(model.muted ? "提醒已静默：只显示变化，不累计偏离提醒。" : model.validationMode ? "验证模式：达到持续时间只显示事件，不发姿态系统通知。" : "姿态通知已启用；同类冷却和系统专注模式仍可能让通知暂不出现。")
                            .font(.caption)
                    }.padding(8)
                }
                }
                if model.baseline == nil && model.adaptation == nil {
                    Text("校准前：让背部和双脚有支撑，肩膀放松、上臂自然靠近身体，正面看屏幕；不要刻意挺胸或夹肩。校准只记录你选择的参考姿势，不能验证它是否健康。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text(model.latestNotice).font(.callout).textSelection(.enabled)
                HStack {
                    if model.pauseUntil != nil { Button("恢复检测") { model.resume() } } else { Button("暂停检测30分钟") { model.pause() }.disabled(!model.requested) }
                    if model.muted { Button("恢复提醒") { model.unsnooze() } } else { Button("稍后提醒10分钟") { model.snooze() } }
                    Spacer()
                    Button("我已活动") { model.activityDone() }
                }
                Text("活动计时：\(Int(model.activityElapsed/60)) / \(Int(model.preferences.activityInterval/60)) 分钟 · \(model.activityEnabled ? "已开启" : "已关闭")").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 12)
        }
    }
    private var settings: some View {
        Form {
            Section("姿态提醒") {
                Text("系统通知：\(model.notificationState)")
                HStack { Button("申请通知权限") { model.requestNotifications() }; Button("刷新权限") { model.refreshNotifications() } }
                Text("提醒始终无声；系统勿扰可能隐藏通知。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("持续偏离")
                    TextField("秒数",value:Binding(get:{Int(model.preferences.dwell)},set:{model.preferences.dwell=Double(min(120,max(1,$0)))}),format:.number.grouping(.never))
                        .frame(width:65).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("持续偏离秒数，1至120秒")
                    Text("秒")
                    Stepper("调整秒数",value:$model.preferences.dwell,in:1...120,step:1).labelsHidden()
                    Button("设为5秒") {model.preferences.dwell=5}
                }
                Text("可配置1–120秒，默认5秒；修改后从零重新计时。只在持续超线后形成事件，通知仍受验证模式和冷却限制。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("同类冷却", selection: $model.preferences.cooldown) { ForEach([300.0,600,1200], id: \.self) { Text("\(Int($0/60))分钟").tag($0) } }
                Picker("灵敏度", selection: $model.preferences.sensitivity) { Text("低").tag(1.4); Text("标准").tag(1.0); Text("高").tag(0.7) }
                Text("当前提醒线：头部 \(Issue.headDown.formatted(model.effectiveThreshold(.headDown))) · 头肩横向偏移 \(Issue.lean.formatted(model.effectiveThreshold(.lean))) · 双肩高低差 \(Issue.shoulders.formatted(model.effectiveThreshold(.shoulders)))。双肩抬高 \(Issue.shrug.formatted(model.effectiveThreshold(.shrug)))。均相对校准参考，非医学标准。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("双肩抬高为试用检测：两侧肩耳距离都缩短才计时，默认线为8%肩宽。需重新校准并保持双耳可见；可独立关闭。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Issue.allCases, id: \.self) { issue in
                    Toggle(issue.title, isOn: Binding(get: { model.enabled.contains(issue) }, set: { if $0 { model.enabled.insert(issue) } else { model.enabled.remove(issue) }; model.save() }))
                }
            }
            Section("活动提醒") {
                Toggle("独立活动提醒", isOn: $model.activityEnabled)
                Picker("提醒间隔", selection: $model.preferences.activityInterval) { ForEach([1800.0,2700,3600], id: \.self) { Text("\(Int($0/60))分钟").tag($0) } }
                Text("停止摄像头后仍可计时。离开画面不自动计作完成活动。").font(.caption).foregroundStyle(.secondary)
            }
            Section("个人适配") {
                Text("通过舒适参考与自然动作估算个人提醒线；这是数值校准，不是模型训练或医学极限测试。")
                Button("重新进行个人适配") {selectedTab=0; model.startAdaptation()}.disabled(!model.capturing || model.calibrating)
                Text(model.personalProfile == nil ? "当前使用默认提醒线。" : "已应用个人提醒线；灵敏度在个人线基础上调整。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("本地数据") {
                Text("仅保存偏好和数值基线；不保存影像、关键点轨迹或历史。手动启动，不随登录启动。")
                Button("清除校准参数", role: .destructive) { model.clearCalibration() }
            }
        }.formStyle(.grouped)
        .onChange(of: model.preferences.dwell) { model.save() }
        .onChange(of: model.preferences.cooldown) { model.save() }
        .onChange(of: model.preferences.sensitivity) { model.save() }
        .onChange(of: model.preferences.activityInterval) { model.save() }
        .onChange(of: model.activityEnabled) { model.save() }
    }
    private var validation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("先验证，再相信提醒").font(.title.bold())
                Text("头部使用 Apple Vision，肩部使用随应用附带的 MediaPipe 本地模型。无需联网或 Python。")
                Text("有效画面：\(model.validFrames) / \(model.totalFrames) 帧（当前开启周期）")
                if model.totalFrames > 0 { Text(String(format: "完整指标可用率 %.1f%%", Double(model.validFrames)/Double(model.totalFrames)*100)) }
                Text("1. 开启预览，让头部和双肩完整入镜，稳定校准约10秒。\n2. 正常办公5分钟，完整指标可用率目标≥90%。\n3. 低头、头肩横向偏移、双肩高低差、双肩抬高各测试5次，每次保持超过所设持续时间（当前\(Int(model.preferences.dwell))秒）再恢复。\n4. 正常打字、喝水、转头、后靠共30分钟，误事件目标≤1次。\n5. 未通过的指标请关闭并记录；不能因此宣称整个首版已经通过验收。")
                Text("头部俯仰使用面部角度，按系统定义的向下方向比较个人基线；实际方向表现与误报仍待验证，提示保持中性。双肩抬高根据同一目标的双耳和双肩估计，耳朵遮挡或头部运动明显时不可判断，也不能区分所有头部位移。圆肩、二郎腿、骨盆和腰椎不在检测范围内。已锁定目标后会忽略背景人脸；遮挡、目标丢失或多人靠近无法区分时暂停，需重新锁定。").foregroundStyle(.secondary)
                if model.validationMode {
                    Button("我已试用，启用姿态系统通知") { model.acceptTrial(); model.requestNotifications() }.buttonStyle(.borderedProminent)
                    Text("这只是你选择开启提醒，不会把应用标记为通过医学或完整产品验收。").font(.caption)
                } else { Label("姿态系统通知已启用，仍属试用检测", systemImage: "bell") }
                Link("参考：OSHA 舒适、有支撑的工作姿势", destination:URL(string:"https://www.osha.gov/etools/computer-workstations/positions/")!)
                Text("这些指南支持舒适、放松、有支撑并经常改变姿势，不提供本应用的11.5°、18%肩宽或8°检测线。头肩正面画面无法评价腰背、骨盆、二郎腿或圆肩。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("资源占用与60分钟能耗、锁屏/唤醒、摄像头占用和真实通知仍需设备实测。校准和可用率不代表检测准确率。")
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ThresholdRow: View {
    let issue: Issue
    let reading: ThresholdReading?
    let threshold: Double
    let unavailable: String
    private var tint: Color {
        guard let reading else {return .secondary}
        switch reading.phase {
        case .below: return .mint
        case .approaching, .counting: return .orange
        case .active: return .red
        case .recovering: return .blue
        case .muted: return .secondary
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            HStack(alignment:.firstTextBaseline) {
                Text(issue.title).font(.headline)
                Spacer()
                Text(reading?.label ?? unavailable).foregroundStyle(tint).font(.callout.bold()).monospacedDigit()
            }
            HStack {
                Text(reading.map {"当前变化 \(issue.formatted($0.deviation))"} ?? "当前变化 —")
                Spacer()
                Text("提醒线 \(issue.formatted(threshold))")
            }.font(.caption).monospacedDigit()
            GeometryReader { proxy in
                ZStack(alignment:.leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    if let reading {
                        Capsule().fill(tint).frame(width:proxy.size.width*min(1,max(0,reading.ratio)/1.5))
                    }
                    Rectangle().fill(Color.primary).frame(width:2,height:12).offset(x:proxy.size.width/1.5-1)
                }
            }.frame(height:8).accessibilityLabel("提醒线100%")
            HStack {
                Text(reading.map {"提醒线的 \($0.formattedRatio)"} ?? "尚无有效读数")
                Spacer()
                Text("┃100% 提醒线")
            }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            Text(issue.explanation).font(.caption).foregroundStyle(.secondary)
            if let reading {
                if reading.phase == .active || reading.phase == .counting {
                    Text(issue.actionHint).font(.caption).foregroundStyle(tint)
                }
                if reading.phase == .active || reading.phase == .recovering {
                    Text("恢复线 \(issue.formatted(reading.recoveryThreshold))，稳定3秒。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
