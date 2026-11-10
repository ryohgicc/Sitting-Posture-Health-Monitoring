import Foundation
import CoreGraphics
import PostureCore
import MediaPipeBridge

/// Serial inference only; neither the adapter nor the runtime writes input frames to disk.
final class MediaPipePose {
    private var detector: OpaquePointer?
    private(set) var issue: String?
    init() {
        // Bundle for packaged app; executable ancestry for swift run / local development.
        var candidates=[Bundle.main.resourceURL?.appendingPathComponent("Models").path].compactMap { $0 }
        var ancestor=URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        if Bundle.main.bundleURL.pathExtension != "app" {
            for _ in 0..<7 { candidates.append(ancestor.appendingPathComponent("Vendor").path); ancestor.deleteLastPathComponent() }
        }
        guard let dir=candidates.first(where:{FileManager.default.fileExists(atPath:$0+"/pose_landmarker_lite.task") && FileManager.default.fileExists(atPath:$0+"/libmediapipe.dylib")}) else {
            issue="缺少本地肩部模型，请重新构建应用。";return
        }
        var error=[CChar](repeating:0,count:1024)
        detector=pp_create(dir+"/libmediapipe.dylib",dir+"/pose_landmarker_lite.task",&error,Int32(error.count))
        if detector == nil {issue=String(cString:error)}
    }
    deinit {if let detector {pp_close(detector)}}
    func bodies(image: CGImage) -> [BodyAnchor] {
        guard let detector else {return []}
        let w=image.width,h=image.height
        guard w > 0, h > 0, w <= 4096, h <= 4096 else {issue="肩部分析画面尺寸无效";return []}
        var data=[UInt8](repeating:0,count:w*h*4)
        let rendered=data.withUnsafeMutableBytes { bytes -> Bool in
            guard let ctx=CGContext(data:bytes.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {return false}
            ctx.draw(image,in:CGRect(x:0,y:0,width:w,height:h));return true
        }
        guard rendered else {issue="无法准备肩部分析画面";return []}
        var results=[PPBody](repeating:PPBody(),count:3)
        var error=[CChar](repeating:0,count:1024)
        let count=pp_detect(detector,&data,Int32(w),Int32(h),&results,3,&error,Int32(error.count))
        guard count >= 0 else {issue=String(cString:error);return []}
        issue=nil
        func point(_ p: PPPoint) -> Point2? {
            guard p.visibility >= 0.7,p.presence >= 0.7,p.x.isFinite,p.y.isFinite,p.x>=0,p.x<=1,p.y>=0,p.y<=1 else {return nil}
            return Point2(x:Double(p.x),y:1-Double(p.y))
        }
        return results.prefix(Int(count)).map {BodyAnchor(nose:point($0.nose),leftShoulder:point($0.leftShoulder),rightShoulder:point($0.rightShoulder),leftEar:point($0.leftEar),rightEar:point($0.rightEar))}
    }
}
