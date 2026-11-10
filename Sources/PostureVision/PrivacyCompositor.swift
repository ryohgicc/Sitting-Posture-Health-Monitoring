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

/// Serial, frame-local processing. Raw passthrough requires both blur modes off.
public final class PrivacyCompositor {
    private let context = CIContext(options: [.cacheIntermediates: false])
    public init() {}

    public func render(image: CGImage, target: SubjectBox?, blurEnabled: Bool = true, faceBlurEnabled: Bool = false, detectedFaces: [SubjectBox]? = nil) -> PrivatePreview {
        guard faceBlurEnabled else { return backgroundPreview(image:image,target:target,blurEnabled:blurEnabled,detectedFaces:detectedFaces) }
        let source=CIImage(cgImage:image), extent=source.extent
        let blurred=source.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:max(28,extent.width*0.065)]).cropped(to:extent)
        func fallback() -> PrivatePreview {
            PrivatePreview(image:context.createCGImage(blurred,from:extent),targetVisible:false,excludedFaces:0)
        }
        let boxes: [SubjectBox]
        if let detectedFaces { boxes=detectedFaces }
        else {
            let request=VNDetectFaceRectanglesRequest()
            do { try VNImageRequestHandler(cgImage:image,orientation:.up).perform([request]) }
            catch { return fallback() }
            boxes=(request.results ?? []).map { face in
                let b=face.boundingBox
                return SubjectBox(x:b.minX,y:b.minY,width:b.width,height:b.height)
            }
        }
        guard !boxes.isEmpty, boxes.allSatisfy(\.valid) else { return fallback() }
        let base=backgroundPreview(image:image,target:target,blurEnabled:blurEnabled,detectedFaces:boxes)
        guard let baseImage=base.image else { return fallback() }
        var mask=CIImage(color:.black).cropped(to:extent)
        // Expand fresh face boxes; never preserve the selected user's face in this mode.
        for b in boxes {
            let rect=CGRect(x:(b.x-b.width*0.35)*extent.width,y:(b.y-b.height*0.35)*extent.height,width:b.width*1.7*extent.width,height:b.height*1.7*extent.height).intersection(extent)
            mask=CIImage(color:.white).cropped(to:rect).composited(over:mask)
        }
        let result=blurred.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:CIImage(cgImage:baseImage),kCIInputMaskImageKey:mask])
        return PrivatePreview(image:context.createCGImage(result,from:extent),targetVisible:base.targetVisible,excludedFaces:base.excludedFaces)
    }

    private func backgroundPreview(image: CGImage, target: SubjectBox?, blurEnabled: Bool, detectedFaces: [SubjectBox]?) -> PrivatePreview {
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
            let faces = detectedFaces == nil ? VNDetectFaceRectanglesRequest() : nil
            var requests: [VNRequest]=[request]
            if let faces {requests.append(faces)}
            try handler.perform(requests)
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
            let boxes=detectedFaces ?? (faces?.results ?? []).map { face -> SubjectBox in
                let b=face.boundingBox
                return SubjectBox(x:b.minX,y:b.minY,width:b.width,height:b.height)
            }
            guard let targetIndex=PrivacySelection.targetFace(target:target,faces:boxes) else {return fallback()}
            let others=boxes.indices.filter {$0 != targetIndex}.map {boxes[$0]}
            for b in others {
                let rect = CGRect(x:(b.x-b.width*0.35)*extent.width,y:(b.y-b.height*0.35)*extent.height,width:b.width*1.7*extent.width,height:b.height*1.7*extent.height)
                let black = CIImage(color: .black).cropped(to: rect)
                mask = black.composited(over: mask)
            }
            let result = source.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey:background,kCIInputMaskImageKey:mask])
            return PrivatePreview(image:context.createCGImage(result,from:extent),targetVisible:true,excludedFaces:others.count)
        } catch { return fallback() }
    }
}
