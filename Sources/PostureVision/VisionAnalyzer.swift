import Foundation
import Vision
import CoreGraphics
import PostureCore

public struct AnalyzedPose {
    public let metrics: PoseMetrics?
    public let points: [CGPoint]
    public let faceBox: SubjectBox?
    public let status: SubjectStatus
    public let newLock: Bool
    public let reason: String
    public let faces: Int
    public let bodies: Int
}

/// Shared by camera and offline probe so replay exercises the actual production pipeline.
public final class VisionAnalyzer {
    private var tracker = SubjectTracker()
    private var scale = ScaleContinuity()
    private lazy var pose = MediaPipePose()
    public init() {}
    public func reset(pick: Point2? = nil) { tracker.reset(pick: pick); scale = ScaleContinuity() }
    public func analyze(handler: VNImageRequestHandler, width: Double, height: Double, now: Double, image: CGImage? = nil) throws -> AnalyzedPose {
        let faceRequest = VNDetectFaceRectanglesRequest()
        try handler.perform([faceRequest])
        let faces = (faceRequest.results ?? []).filter { $0.confidence > 0.6 }
        let boxes = faces.map { SubjectBox(x:$0.boundingBox.minX,y:$0.boundingBox.minY,width:$0.boundingBox.width,height:$0.boundingBox.height) }
        let selected = tracker.select(boxes,now:now)
        func output(_ metrics: PoseMetrics? = nil, points: [CGPoint] = [], box: SubjectBox? = nil, reason: String, bodies: Int = 0) -> AnalyzedPose {
            AnalyzedPose(metrics:metrics,points:points,faceBox:box,status:selected.status,newLock:selected.newLock,reason:reason,faces:faces.count,bodies:bodies)
        }
        guard let index = selected.index else {
            let message: String
            switch selected.status {
            case .needsReset: message = "目标已丢失，请回到原位并点“重新锁定我”，再校准。"
            case .ambiguous: message = "目标不明确，请在预览里点自己的脸以锁定。"
            case .missing: message = "暂时看不到已锁定的你，不会切到背景同事。"
            default: message = "请面向屏幕；也可在预览里点自己的脸。"
            }
            return output(reason: message)
        }
        let face = faces[index], box = boxes[index]
        let outline = CGPoint(x:box.center.x,y:box.center.y)
        guard let yaw = face.yaw?.doubleValue, abs(yaw) < 0.45 else {
            return output(points:[outline],box:box,reason:"已锁定你；转头期间暂停姿态判断。")
        }
        let anchors=image.map {pose.bodies(image:$0)} ?? []
        let matched = SubjectAssociation.bodyIndex(for:box,candidates:anchors)
        var lateral: Double?, tilt: Double?, overlay = [outline]
        if let matched, let l=anchors[matched].leftShoulder, let r=anchors[matched].rightShoulder, let nose=anchors[matched].nose {
            func px(_ p: Point2) -> Point2 { Point2(x:p.x*width,y:(1-p.y)*height) }
            let shoulderWidth = hypot((l.x-r.x)*width,(l.y-r.y)*height)
            if scale.accept(width:shoulderWidth,now:now) {
                let g = FrameGeometry(leftShoulder:px(l),rightShoulder:px(r),head:px(nose))
                lateral=g.lateral; tilt=g.shoulderTilt
                overlay=[CGPoint(x:l.x,y:l.y),CGPoint(x:r.x,y:r.y),CGPoint(x:nose.x,y:nose.y)]
            }
        }
        let metrics = PoseMetrics(headPitch:face.pitch?.doubleValue,lateral:lateral,shoulderTilt:tilt)
        let suffix = faces.count > 1 ? "，已忽略背景人脸" : ""
        return output(metrics.usable ? metrics : nil,points:overlay,box:box,reason:metrics.complete ? "已锁定你，头肩可用（MediaPipe）\(suffix)" : "已锁定你\(suffix)；\(image == nil ? "无法准备肩部画面" : (pose.issue == nil ? "肩部未可靠识别，仅使用可用的头部角度。" : "本地肩部模型不可用，请重新构建应用。"))",bodies:anchors.count)
    }
}
