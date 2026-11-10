import AppKit
import SwiftUI
import UserNotifications
import PostureCore

@MainActor
final class AppModel: ObservableObject {
    let camera = CameraPipeline()
    @Published var captureState = "未开启"
    @Published var capturing = false
    @Published var requested = false
    @Published var reason = "点击开启后才会访问摄像头。"
    @Published var points: [CGPoint] = []
    @Published var previewImage: CGImage?
    @Published var previewTargetVisible = false
    @Published var subjectBox: SubjectBox?
    @Published var sourceAspect = 4.0/3
    @Published var metrics: PoseMetrics?
    @Published var baseline: PoseMetrics?
    @Published var personalProfile: PersonalProfile?
    @Published var adaptation: AdaptationSession?
    @Published var adaptationMessage = ""
    @Published var hasPersonalAdaptation = false
    private var adaptationLastUsable: Double?
    @Published var calibrating = false
    @Published var calibrationProgress = 0.0
    @Published var readings: [Issue:ThresholdReading] = [:]
    @Published var deviations: [Issue:Double] = [:]
    @Published var active = Set<Issue>()
    @Published var notificationState = "尚未请求"
    @Published var preferences = Preferences()
    @Published var enabled = Set(Issue.allCases)
    @Published var activityEnabled = true
    @Published var activityElapsed = 0.0
    @Published var pauseUntil: Double?
    @Published var snoozeUntil: Double?
    @Published var validFrames = 0
    @Published var totalFrames = 0
    @Published var latestNotice = "尚无提醒"
    @Published var backgroundBlur = true {
        didSet {
            defaults.set(backgroundBlur,forKey:"backgroundBlur.v1")
            previewRevision=camera.setBackgroundBlur(backgroundBlur)
            previewImage=nil;previewTargetVisible=false
        }
    }
    private var previewRevision = 0
    @Published var showOverlay = true
    @Published var showPreview = true { didSet { camera.setPreviewEnabled(showPreview); if !showPreview { previewImage = nil; previewTargetVisible = false } } }
    @Published var validationMode = true
    private var overlay = OverlayStabilizer()
    private var calibration = CalibrationAccumulator()
    private var calibrationStarted: Double?
    private var judge: PostureJudge?
    private var clock = SessionClock()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var locked = false
    private var sleeping = false
    private var lastFrame: Double?
    private var watchdog = FrameWatchdog()
    private var reminders = ReminderAggregator()
    private let defaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter?
    private let time: () -> Double
    private var livePermitted: Bool { !locked && !sleeping && pauseUntil == nil }
    var now: Double { time() }
    var muted: Bool { snoozeUntil.map { now < $0 } ?? false }

    init(defaults: UserDefaults = .standard, notificationCenter: UNUserNotificationCenter? = .current(), time: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults=defaults; self.notificationCenter=notificationCenter; self.time=time
        backgroundBlur=defaults.object(forKey:"backgroundBlur.v1") == nil ? true : defaults.bool(forKey:"backgroundBlur.v1")
        previewRevision=camera.setBackgroundBlur(backgroundBlur)
        if let data = defaults.data(forKey: "preferences.v1"), let p = try? JSONDecoder().decode(Preferences.self, from: data) { preferences = p.validated }
        if let data = defaults.data(forKey: "baseline.v1"), let b = try? JSONDecoder().decode(PoseMetrics.self, from: data), b.usable,
           abs(b.headPitch ?? 0) <= .pi/2, abs(b.lateral ?? 0) < 2, abs(b.shoulderTilt ?? 0) < .pi/2 {
            baseline = b; judge = PostureJudge(baseline: b, preferences: preferences)
        }
        if let data=defaults.data(forKey:"personalProfile.v1"),
           let profile=(try? JSONDecoder().decode(PersonalProfile.self,from:data))?.validated,
           let baseline, profile.matches(baseline) {
            personalProfile=profile; judge?.profile=profile
        }
        hasPersonalAdaptation=defaults.bool(forKey:"personalAdaptationAccepted.v1")
        if let values = defaults.stringArray(forKey: "enabled.v1") { enabled = Set(values.compactMap(Issue.init(rawValue:))) }
        if !defaults.bool(forKey:"shrugEnabledMigrated.v1") {
            enabled.insert(.shrug)
            defaults.set(enabled.map(\.rawValue),forKey:"enabled.v1")
            defaults.set(true,forKey:"shrugEnabledMigrated.v1")
        }
        if !defaults.bool(forKey:"headForwardEnabledMigrated.v1") {
            enabled.insert(.headForward)
            defaults.set(enabled.map(\.rawValue),forKey:"enabled.v1")
            defaults.set(true,forKey:"headForwardEnabledMigrated.v1")
        }
        if defaults.object(forKey: "activity.v1") != nil { activityEnabled = defaults.bool(forKey: "activity.v1") }
        // Validation mode is explicit: notifications describing posture stay gated until a real trial.
        validationMode = !defaults.bool(forKey: "trialAccepted.v1")
        camera.onFrame = { [weak self] frame in self?.consume(frame) }
        camera.onState = { [weak self] running, text in
            guard let self, self.requested, self.livePermitted else { return }
            self.capturing = running; self.captureState = running ? (self.baseline == nil ? "等待校准" : "监测中") : "摄像头故障"
            self.reason = text
            if running { self.watchdog.start(now: self.now) }
            if !running { self.requested = false; self.camera.stop(); self.clearLive() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.sleeping = true; self?.suspend() } })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.sleeping = false; self?.resumeIfWanted() } })
        let dist = DistributedNotificationCenter.default()
        observers.append(dist.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.locked = true; self?.suspend() } })
        observers.append(dist.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.locked = false; self?.resumeIfWanted() } })
        refreshNotifications()
    }
    func save() {
        cancelAdaptation("设置已修改，个人适配草稿已取消。")
        preferences = preferences.validated
        defaults.set(try? JSONEncoder().encode(preferences), forKey: "preferences.v1")
        defaults.set(enabled.map(\.rawValue), forKey: "enabled.v1")
        defaults.set(activityEnabled, forKey: "activity.v1")
        judge?.preferences = preferences; judge?.enabled = enabled; judge?.resetPending(); readings = [:]; deviations = [:]; active = []
        clock.interval = preferences.activityInterval
        reminders.cancel(channel: "posture")
        if !activityEnabled { reminders.cancel(channel: "activity") }
    }
    func start() {
        guard !requested else { return }
        requested = true; pauseUntil = nil; reason = "正在申请权限或启动摄像头…"; captureState = "正在开启"
        totalFrames = 0; validFrames = 0
        if livePermitted { camera.start() }
    }
    func stop() {
        requested = false; pauseUntil = nil; camera.stop(); capturing = false; captureState = "未开启"; reason = "摄像头已停止；独立活动提醒可继续。"; clearLive()
    }
    func suspend() {
        camera.stop(); capturing = false; clearLive(); captureState = "已暂停"
        _ = clock.tick(now: now, running: false, muted: true)
    }
    private func resumeIfWanted() {
        if requested && livePermitted { captureState = "正在恢复"; camera.start() }
    }
    func pause() {
        guard requested else { return }; pauseUntil = now+1800; suspend(); reason = "检测暂停30分钟，到期且已解锁时自动恢复摄像头。"
    }
    func resume() { pauseUntil = nil; resumeIfWanted() }
    func snooze() { cancelAdaptation("提醒已静默，个人适配草稿已取消。"); reminders.clearPending(); snoozeUntil = now+600; judge?.resetPending(); readings = [:]; deviations = [:]; active = []; latestNotice = "提醒静默10分钟，摄像头仍工作。" }
    func unsnooze() { snoozeUntil = nil; judge?.resetPending(); readings = [:]; deviations = [:]; active = [] }
    func clearLive() {
        cancelAdaptation("检测中断，个人适配草稿已取消。")
        overlay = OverlayStabilizer()
        previewImage = nil; previewTargetVisible = false
        points = []; subjectBox = nil; metrics = nil; judge?.resetPending(); readings = [:]; deviations = [:]; active = []; lastFrame = nil; watchdog.stop(); reminders.clearPending()
        calibrating = false; calibrationProgress = 0; calibrationStarted = nil
    }
    func relock(pick: Point2? = nil) {
        guard capturing else { return }
        cancelAdaptation("已重新锁定，个人适配草稿已取消。")
        invalidatePersonalProfile()
        camera.resetTarget(pick:pick)
        overlay = OverlayStabilizer()
        defaults.removeObject(forKey:"baseline.v1"); baseline=nil; judge=nil
        calibration=CalibrationAccumulator(); calibrating=false; calibrationProgress=0
        previewImage=nil; previewTargetVisible=false
        points=[]; subjectBox=nil; deviations=[:]; readings=[:]; active=[]; reminders.cancel(channel:"posture")
        reason="正在重新锁定，请保持位置；锁定后重新校准。"
    }
    func beginCalibration() {
        guard capturing else { return }; cancelAdaptation("开始重新校准，个人适配草稿已取消。"); calibration = CalibrationAccumulator(); calibrating = true; calibrationProgress = 0; calibrationStarted = now
        judge?.resetPending(); readings = [:]; deviations = [:]; active = []; reminders.cancel(channel: "posture"); reason = "保持舒适稳定姿态约10秒；不必挺胸或夹肩。"
    }
    func clearCalibration() {
        invalidatePersonalProfile()
        defaults.removeObject(forKey: "baseline.v1"); baseline = nil; judge = nil; clearLive()
        if capturing { watchdog.start(now: now) }
        captureState = capturing ? "等待校准" : "未开启"; reason = "参考参数已清除，需要重新校准。"
    }
    func acceptTrial() {
        validationMode = false; defaults.set(true, forKey: "trialAccepted.v1")
        judge?.resetPending(); readings = [:]; deviations = [:]; active = []; latestNotice = "已由你启用姿态通知，仍属于试用检测。"
    }
    func consume(_ frame: CaptureFrame) {
        guard requested, livePermitted, capturing, frame.timestamp.isFinite, now-frame.timestamp >= 0, now-frame.timestamp < 3 else { return }
        lastFrame = frame.timestamp; watchdog.received(now: frame.timestamp); totalFrames += 1
        if frame.metrics?.complete == true { validFrames += 1 }
        if frame.newTarget {
            cancelAdaptation("监测目标已更换，请重新开始个人适配。")
            invalidatePersonalProfile()
            overlay = OverlayStabilizer()
            defaults.removeObject(forKey:"baseline.v1"); baseline=nil; judge=nil
            calibration=CalibrationAccumulator(); calibrating=false; calibrationProgress=0
            reminders.cancel(channel:"posture"); deviations=[:]; readings=[:]; active=[]
        }
        if frame.previewRevision == previewRevision {
            previewImage=showPreview ? frame.previewImage : nil; previewTargetVisible=showPreview && frame.previewTargetVisible
        }
        subjectBox=frame.subjectBox; sourceAspect=frame.sourceAspect
        metrics = frame.metrics; points = overlay.update(frame.points.map {Point2(x:$0.x,y:$0.y)},now:frame.timestamp).map {CGPoint(x:$0.x,y:$0.y)}; reason = frame.reason
        captureState = frame.metrics == nil ? "暂时看不清" : (baseline == nil ? "等待校准" : frame.metrics?.complete == true ? "监测中" : "部分指标不可用")
        if adaptation != nil {
            if let last=adaptationLastUsable, frame.timestamp-last > 3 {
                cancelAdaptation("超过3秒无法判断目标，草稿已取消；请调整画面后重试。")
            } else {
                if frame.metrics?.usable == true {adaptationLastUsable=frame.timestamp}
                adaptation?.update(frame.metrics,now:frame.timestamp)
                captureState="个人适配中 · 不发送姿态通知"
                return
            }
        }
        if calibrating {
            if let m = frame.metrics { calibration.add(m, now: frame.timestamp) }
            else { calibration = CalibrationAccumulator() }
            calibrationProgress = min(1, calibration.duration/10)
            if let b = calibration.result(now: frame.timestamp) {
                invalidatePersonalProfile()
                baseline = b; judge = PostureJudge(baseline: b, preferences: preferences); judge?.enabled = enabled
                defaults.set(try? JSONEncoder().encode(b), forKey: "baseline.v1")
                calibrating = false; calibrationStarted = nil; reason = b.complete ? "校准完成。调整屏幕或椅子后请重新校准。" : "部分校准完成：缺少的指标保持不可用，调整拍摄后可重试。"
            } else if let start = calibrationStarted, now-start > 45 {
                calibrating = false; calibrationStarted = nil; calibrationProgress = 0
                reason = "校准未成功：请保证头肩清楚入镜且稳定，再重试。"
            }
            return
        }
        guard judge != nil else { return }
        judge?.enabled = enabled
        let verdict = judge!.update(frame.metrics, now: frame.timestamp, muted: muted)
        active = verdict.active; deviations = verdict.deviations; readings = verdict.readings
        if verdict.active.isEmpty { reminders.cancel(channel: "posture") }
        if !verdict.alerts.isEmpty {
            let labels = verdict.alerts.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: "、")
            if validationMode { latestNotice = "验证事件：\(labels)持续偏离（未发送姿态通知）" }
            else { notify("\(labels)持续偏离参考姿态，换个姿势或活动一下吧。", posture: true) }
        }
    }
    func tick() {
        if let until = pauseUntil, now >= until { pauseUntil = nil; resumeIfWanted() }
        if let until = snoozeUntil, now >= until { snoozeUntil = nil; judge?.resetPending(); readings = [:]; deviations = [:]; active = [] }
        if capturing, watchdog.age(now: now) > 3 {
            cancelAdaptation("画面中断，个人适配草稿已取消。")
            overlay = OverlayStabilizer()
            previewImage = nil; previewTargetVisible = false
            metrics = nil; points = []; subjectBox = nil; active = []; deviations = [:]; judge?.resetPending(); readings = [:]; deviations = [:]; active = []
            captureState = "暂时看不清"; reason = "画面中断，姿态计时已清空。"
            reminders.cancel(channel: "posture")
            if watchdog.expired(now: now) { requested = false; camera.stop(); capturing = false; watchdog.stop(); captureState = "摄像头故障"; reason = "持续未收到画面，请重新开启。" }
        }
        clock.interval = preferences.activityInterval
        let due = clock.tick(now: now, running: activityEnabled && livePermitted && adaptation == nil, muted: muted || adaptation != nil)
        activityElapsed = clock.elapsed
        if due { notify("已经工作一段时间了，起身走动一下吧。", posture: false) }
        if adaptation == nil, !muted, livePermitted, let messages = reminders.take(now: now) { deliver(messages.joined(separator: "\n")) }
    }
    func effectiveThreshold(_ issue: Issue) -> Double {
        personalProfile?.threshold(for:issue,sensitivity:preferences.sensitivity) ?? issue.entryThreshold(sensitivity:preferences.sensitivity)
    }
    func startAdaptation() {
        guard capturing, !muted, metrics?.usable == true, subjectBox != nil else {
            adaptationMessage="请先开启摄像头并确认目标已锁定；若提醒已静默，请先恢复提醒。"; return
        }
        calibrating=false; calibrationStarted=nil; calibrationProgress=0
        judge?.resetPending(); readings=[:]; deviations=[:]; active=[]; reminders.cancel(channel:"posture")
        reminders.clearPending()
        _ = clock.tick(now:now,running:false,muted:true)
        adaptation=AdaptationSession(preferences:preferences); adaptationLastUsable=now
        adaptationMessage=""
    }
    func cancelAdaptation(_ message: String = "已取消个人适配，保留原来的设置。") {
        guard adaptation != nil else {return}
        adaptation=nil; adaptationLastUsable=nil; adaptationMessage=message
        judge?.resetPending(); readings=[:]; deviations=[:]; active=[]; reminders.cancel(channel:"posture")
    }
    func recordAdaptation() {adaptation?.record()}
    func skipAdaptation() {adaptation?.skip()}
    func adjustAdaptation(_ issue: Issue, factor: Double) {adaptation?.adjust(issue,factor:factor)}
    func reviewAdaptation() {adaptation?.review()}
    func applyAdaptation() {
        guard capturing, !muted, let last=adaptationLastUsable, now-last < 1,
              adaptation?.step == .review, let profile=adaptation?.profile?.validated else {
            adaptationMessage="当前目标或结果不可用，请回到镜头前再确认。"; return
        }
        baseline=profile.baseline; personalProfile=profile
        defaults.set(try? JSONEncoder().encode(profile.baseline),forKey:"baseline.v1")
        defaults.set(try? JSONEncoder().encode(profile),forKey:"personalProfile.v1")
        defaults.set(true,forKey:"personalAdaptationAccepted.v1"); hasPersonalAdaptation=true
        judge=PostureJudge(baseline:profile.baseline,preferences:preferences,profile:profile); judge?.enabled=enabled
        cancelAdaptation("个人参考和提醒线已应用。移动屏幕、椅子或摄像头后，请重新适配。")
        reason=adaptationMessage
    }
    private func invalidatePersonalProfile() {
        personalProfile=nil; judge?.profile=nil; defaults.removeObject(forKey:"personalProfile.v1")
    }
    func activityDone() { clock.reset(now: now); activityElapsed = 0; reminders.cancel(channel: "activity") }
    func requestNotifications() {
        notificationCenter?.requestAuthorization(options: [.alert]) { [weak self] _, _ in Task { @MainActor in self?.refreshNotifications() } }
    }
    func refreshNotifications() {
        notificationCenter?.getNotificationSettings { [weak self] settings in
            Task { @MainActor in self?.notificationState = settings.authorizationStatus == .authorized ? "已允许 · 无声" : settings.authorizationStatus == .denied ? "未允许，请在系统设置中开启" : "尚未请求" }
        }
    }
    private func notify(_ text: String, posture: Bool) {
        latestNotice = text
        reminders.enqueue(text, channel: posture ? "posture" : "activity", now: now)
    }
    private func deliver(_ text: String) {
        let content = UNMutableNotificationContent(); content.title = "坐姿搭子"; content.body = text
        content.sound = nil
        let req = UNNotificationRequest(identifier: "posture-pal-current", content: content, trigger: nil)
        notificationCenter?.add(req) { [weak self] error in
            if let error { Task { @MainActor in self?.latestNotice = "系统通知未能发送：\(error.localizedDescription)" } }
        }
    }
    func shutdown() { timer?.invalidate(); camera.stop() }
}

import AVFoundation
