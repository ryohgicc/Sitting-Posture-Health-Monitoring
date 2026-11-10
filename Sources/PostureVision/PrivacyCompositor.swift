import Foundation
import Vision
import CoreImage
import CoreVideo
import PostureCore

public struct PrivatePreview {
    public let image: CGImage?
    public let targetVisible: Bool
    public let excludedFaces: Int
}

/// Serial, frame-local processing. Raw passthrough requires explicit blur opt-out.
public final class PrivacyCompositor {
    private let context = CIContext(options: [.cacheIntermediates: false])
    public init() {}

    public func render(image: CGImage, target: SubjectBox?, blurEnabled: Bool = true) -> PrivatePreview {
        if !blurEnabled { return PrivatePreview(image:image,targetVisible:false,excludedFaces:0) }
        let source = CIImage(cgImage: image), extent = source.extent
        let background = source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(28, extent.width*0.065)]).cropped(to: extent)
        func fallback() -> PrivatePreview {
            PrivatePreview(image: context.createCGImage(background, from: extent), targetVisible: false, excludedFaces: 0)
        }
        guard let target, target.valid else { return fallback() }
        do {
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            let request = VNGeneratePersonInstanceMaskRequest()
            let faces = VNDetectFaceRectanglesRequest()
            try handler.perform([request, faces])
            guard let observation = request.results?.first else { return fallback() }
            var coverage: [Int: Double] = [:]
            // Probe mask values at points safely inside the selected face. A generic
            // all-person mask would also reveal coworkers, so evaluate each instance.
            for instance in observation.allInstances {
                let buffer = try observation.generateMask(forInstances: IndexSet(integer: instance))
                CVPixelBufferLockBaseAddress(buffer, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
                guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float,
                      let base = CVPixelBufferGetBaseAddress(buffer) else { continue }
                let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
                let stride = CVPixelBufferGetBytesPerRow(buffer)
                var sum = 0.0
                for row in 0..<5 {
                    for col in 0..<5 {
                        let x = min(width-1,max(0,Int((target.x+target.width*(0.25+Double(col)*0.125))*Double(width))))
                        let y = min(height-1,max(0,Int((1-target.y-target.height*(0.25+Double(row)*0.125))*Double(height))))
                        let value = base.advanced(by: y*stride).assumingMemoryBound(to: Float.self)[x]
                        if value.isFinite { sum += Double(max(0,min(1,value))) }
                    }
                }
                coverage[instance] = sum/25
            }
            guard let chosen = PrivacySelection.instance(coverage: coverage) else { return fallback() }
            let scaled = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: chosen), from: handler)
            var mask = CIImage(cvPixelBuffer: scaled)
            mask = mask.transformed(by: CGAffineTransform(scaleX: extent.width/mask.extent.width, y: extent.height/mask.extent.height))
            // Erode uncertain silhouette edges; exclude other faces even if instance
            // segmentation merged a bystander with the foreground person.
            mask = mask.applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 3])
            let detected=faces.results ?? []
            let boxes=detected.map { face -> SubjectBox in
                let b=face.boundingBox
                return SubjectBox(x:b.minX,y:b.minY,width:b.width,height:b.height)
            }
            guard let targetIndex=PrivacySelection.targetFace(target:target,faces:boxes) else {return fallback()}
            let others=detected.indices.filter {$0 != targetIndex}.map {detected[$0]}
            for face in others {
                let b = face.boundingBox
                let rect = CGRect(x:(b.minX-b.width*0.35)*extent.width,y:(b.minY-b.height*0.35)*extent.height,width:b.width*1.7*extent.width,height:b.height*1.7*extent.height)
                let black = CIImage(color: .black).cropped(to: rect)
                mask = black.composited(over: mask)
            }
            let result = source.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey:background,kCIInputMaskImageKey:mask])
            return PrivatePreview(image:context.createCGImage(result,from:extent),targetVisible:true,excludedFaces:others.count)
        } catch { return fallback() }
    }
}
