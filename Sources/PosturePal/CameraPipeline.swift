import AppKit
import AVFoundation
import Vision
import PostureVision
import CoreImage
import PostureCore

struct CaptureFrame {
    var previewImage: CGImage? = nil
    var previewTargetVisible = false
    var previewRevision = 0
    let metrics: PoseMetrics?
    let points: [CGPoint] // normalized in Vision coordinates
    let reason: String
    let timestamp: Double
    var subjectBox: SubjectBox? = nil
    var sourceAspect: Double = 4.0/3
    var newTarget = false
}

final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "PosturePal.camera", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "PosturePal.vision", qos: .utility)
    private let gate = GenerationGate()
    private var lastAnalysis = 0.0
    private let analyzer = VisionAnalyzer()
    private let privacy = PrivacyCompositor()
    private let targetLock = NSLock()
    private var targetResetPending = false
    private var earliestSampleTime = -Double.infinity
    private let previewLock = NSLock()
    private var previewEnabled = false
    private var blurEnabled = true
    private var faceBlurEnabled = true
    private var previewRevision = 0
    @discardableResult
    func setPreviewEnabled(_ enabled: Bool) -> Int {
        previewLock.lock(); defer {previewLock.unlock()}
        if previewEnabled != enabled {previewEnabled=enabled; previewRevision += 1}
        return previewRevision
    }
    func setBackgroundBlur(_ enabled: Bool) -> Int {
        previewLock.lock(); defer {previewLock.unlock()}
        blurEnabled=enabled;previewRevision += 1;return previewRevision
    }
    func setFaceBlur(_ enabled: Bool) -> Int {
        previewLock.lock(); defer {previewLock.unlock()}
        faceBlurEnabled=enabled;previewRevision += 1;return previewRevision
    }
    private var previewOptions: (visible:Bool,blur:Bool,faceBlur:Bool,revision:Int) {
        previewLock.lock(); defer {previewLock.unlock()}
        return (previewEnabled,blurEnabled,faceBlurEnabled,previewRevision)
    }
    private let imageContext = CIContext(options:[.cacheIntermediates:false])
    private var frameGeneration = -1
    private var runtimeObserver: NSObjectProtocol?
    var onFrame: ((CaptureFrame) -> Void)?
    var onState: ((Bool, String) -> Void)?

    override init() {
        super.init()
        runtimeObserver = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { [weak self] _ in
            self?.stop()
            if let self { self.state(false, "摄像头中断，请停止后重新开启监测。", self.gate.current) }
        }
    }
    deinit { if let o = runtimeObserver { NotificationCenter.default.removeObserver(o) } }
    private func bump() -> Int { gate.advance() }
    private func current(_ value: Int) -> Bool { gate.accepts(value) }
    private func state(_ running: Bool, _ message: String, _ ticket: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.current(ticket) else { return }; self.onState?(running, message)
        }
    }
    func start() {
        targetLock.lock()
        targetResetPending=false; earliestSampleTime = -Double.infinity
        let ticket = bump()
        targetLock.unlock()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure(ticket)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self, self.current(ticket) else { return }
                if granted { self.configure(ticket) } else { self.state(false, "未获得摄像头权限，可在系统设置 → 隐私与安全性 → 摄像头中开启。", ticket) }
            }
        default: state(false, "摄像头权限未开启。请到系统设置 → 隐私与安全性 → 摄像头开启后重试。", ticket)
        }
    }
    private func configure(_ ticket: Int) {
        queue.async { [weak self] in
            guard let self, self.current(ticket) else { return }
            if !self.session.inputs.isEmpty {
                if !self.session.isRunning { self.session.startRunning() }
                if self.current(ticket) { self.state(self.session.isRunning, self.session.isRunning ? "监测中" : "摄像头无法启动", ticket) }
                return
            }
            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else {
                    self.state(false, "找不到内置摄像头。本版仅支持内置摄像头。", ticket); return
                }
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.setSampleBufferDelegate(self, queue: self.frameQueue)
                self.session.beginConfiguration()
                self.session.sessionPreset = .vga640x480
                guard self.session.canAddInput(input), self.session.canAddOutput(output) else {
                    self.session.commitConfiguration(); self.state(false, "摄像头配置失败。", ticket); return
                }
                self.session.addInput(input); self.session.addOutput(output)
                self.session.commitConfiguration()
                guard self.current(ticket) else { return }
                self.session.startRunning()
                if self.current(ticket) { self.state(self.session.isRunning, self.session.isRunning ? "等待有效画面" : "摄像头无法启动", ticket) }
            } catch { self.state(false, "无法访问摄像头：\(error.localizedDescription)", ticket) }
        }
    }
    func stop() {
        _ = bump()
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            // Removing inputs releases the device instead of just stopping inference.
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }
            self.session.commitConfiguration()
        }
    }
    func resetTarget(pick: Point2? = nil) {
        targetLock.lock()
        targetResetPending = true
        earliestSampleTime = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
        let ticket=bump()
        targetLock.unlock()
        frameQueue.async { [weak self] in
            guard let self, self.current(ticket) else { return }
            self.analyzer.reset(pick:pick)
            self.frameGeneration=ticket
            self.targetLock.lock()
            if self.current(ticket) { self.targetResetPending=false }
            self.targetLock.unlock()
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        targetLock.lock()
        let resetPending=targetResetPending, cutoff=earliestSampleTime, ticket=gate.current
        targetLock.unlock()
        guard !resetPending else { return }
        if cutoff.isFinite {
            guard let clock=session.synchronizationClock else { return }
            let hostTime=CMSyncConvertTime(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), from:clock, to:CMClockGetHostTimeClock())
            let sampleTime=CMTimeGetSeconds(hostTime)
            guard sampleTime.isFinite, sampleTime >= cutoff else { return }
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now-lastAnalysis >= 0.2, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysis = now
        if frameGeneration != ticket { analyzer.reset(); frameGeneration = ticket }
        autoreleasepool {
            let w=Double(CVPixelBufferGetWidth(buffer)), h=Double(CVPixelBufferGetHeight(buffer))
            do {
                let cgImage=imageContext.createCGImage(CIImage(cvPixelBuffer:buffer),from:CGRect(x:0,y:0,width:w,height:h))
                let result = try analyzer.analyze(handler:VNImageRequestHandler(cvPixelBuffer:buffer,orientation:.up),width:w,height:h,now:now,image:cgImage)
                guard current(ticket) else { return }
                let options=previewOptions
                let processed = options.visible ? cgImage.map { privacy.render(image:$0,target:result.status == .locked ? result.faceBox : nil,blurEnabled:options.blur,faceBlurEnabled:options.faceBlur,detectedFaces:result.faceBoxes) } : nil
                guard current(ticket), ProcessInfo.processInfo.systemUptime-now < 3 else { return }
                emit(CaptureFrame(previewImage:processed?.image,previewTargetVisible:processed?.targetVisible ?? false,previewRevision:options.revision,metrics:result.metrics,points:result.points,reason:result.reason,timestamp:now,subjectBox:result.faceBox,sourceAspect:w/h,newTarget:result.newLock),ticket)
            } catch {
                emit(CaptureFrame(previewRevision:previewOptions.revision,metrics:nil,points:[],reason:"当前画面无法分析，请调整光线或重新锁定。",timestamp:now),ticket)
            }
        }
    }

    private func emit(_ frame: CaptureFrame, _ ticket: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.current(ticket) else { return }; self.onFrame?(frame)
        }
    }
}
