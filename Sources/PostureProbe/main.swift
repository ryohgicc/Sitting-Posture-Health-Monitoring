import AppKit
import Vision
import PostureVision

// No camera, network or image writes. Reads only a user-specified image.
let args = Array(CommandLine.arguments.dropFirst())
guard let path=args.first, let image=NSImage(contentsOfFile:path) else {
    fputs("Usage: PostureProbe image-path [--screenshot] [--multi] [--require-shoulders] [--require-shrug] [--require-head-forward] [--privacy] [--benchmark] [--independent-faces]\n",stderr); exit(2)
}
var rect=NSRect(origin:.zero,size:image.size)
guard let cg=image.cgImage(forProposedRect:&rect,context:nil,hints:nil) else { exit(2) }
var source: CGImage
if args.contains("--screenshot") {
    guard let cropped=cg.cropping(to:CGRect(x:Double(cg.width)*0.252,y:Double(cg.height)*0.267,width:Double(cg.width)*0.496,height:Double(cg.height)*0.260)) else { exit(2) }
    source=cropped
} else { source=cg }
let analyzer=VisionAnalyzer()
func analyze(_ image: CGImage, now: Double) throws -> AnalyzedPose {
    try analyzer.analyze(handler:VNImageRequestHandler(cgImage:image,orientation:.up),width:Double(image.width),height:Double(image.height),now:now,image:image)
}

func edgeEnergy(_ image: CGImage, box: CGRect) -> Double {
    let w=image.width,h=image.height
    var bytes=[UInt8](repeating:0,count:w*h*4)
    return bytes.withUnsafeMutableBytes { memory in
        guard let ctx=CGContext(data:memory.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {return 0}
        ctx.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
        let pixels=memory.bindMemory(to:UInt8.self)
        var total=0.0,count=0
        for y in max(1,Int(box.minY*Double(h)))..<min(h-1,Int(box.maxY*Double(h))) {
            for x in max(1,Int(box.minX*Double(w)))..<min(w-1,Int(box.maxX*Double(w))) {
                for channel in 0..<3 {
                    let i=(y*w+x)*4+channel
                    total += abs(Double(pixels[i])-Double(pixels[i+4]))
                    total += abs(Double(pixels[i])-Double(pixels[i+w*4]))
                    count += 2
                }
            }
        }
        return count > 0 ? total/Double(count) : 0
    }
}
func verifyPrivacy(source: CGImage, processed: CGImage, target: CGRect, background: CGRect) -> Bool {
    let faceRatio=edgeEnergy(processed,box:target)/max(0.001,edgeEnergy(source,box:target))
    let backgroundRatio=edgeEnergy(processed,box:background)/max(0.001,edgeEnergy(source,box:background))
    print("privacy detail targetRatio=\(faceRatio) backgroundRatio=\(backgroundRatio)")
    return faceRatio > 0.55 && backgroundRatio < 0.25
}

if args.contains("--benchmark") {
    // Same supplied image, transient processing only. Warm up model before timing.
    let compositor=PrivacyCompositor()
    var last=try analyze(source,now:0)
    _ = compositor.render(image:source,target:last.faceBox,detectedFaces:args.contains("--independent-faces") ? nil : last.faceBoxes)
    let count=20
    func wallTime() -> Double {ProcessInfo.processInfo.systemUptime}
    var inference=[Double](),preview=[Double]()
    for n in 1...count {
        try autoreleasepool {
            let start=wallTime()
            last=try analyze(source,now:Double(n)*0.2)
            let end=wallTime();inference.append((end-start)*1000)
            _ = compositor.render(image:source,target:last.faceBox,detectedFaces:args.contains("--independent-faces") ? nil : last.faceBoxes)
            preview.append((wallTime()-end)*1000)
        }
    }
    func stats(_ values:[Double])->String {
        let sorted=values.sorted()
        return String(format:"mean=%.2fms median=%.2fms p95=%.2fms",values.reduce(0,+)/Double(values.count),sorted[values.count/2],sorted[Int(Double(values.count-1)*0.95)])
    }
    print("benchmark frames=\(count) size=\(source.width)x\(source.height) inference \(stats(inference)) privacy \(stats(preview))")
    exit(last.metrics?.headPitch == nil ? 1 : 0)
}

let result=try analyze(source,now:0)
if args.contains("--privacy") {
    let compositor = PrivacyCompositor()
    let start = ProcessInfo.processInfo.systemUptime
    let privateFrame = compositor.render(image:source,target:result.faceBox,detectedFaces:args.contains("--independent-faces") ? nil : result.faceBoxes)
    print("privacy ms=\((ProcessInfo.processInfo.systemUptime-start)*1000)")
    let fallback = compositor.render(image:source,target:nil)
    print("privacy target=\(privateFrame.targetVisible) otherFaces=\(privateFrame.excludedFaces) rendered=\(privateFrame.image != nil) fallback=\(fallback.image != nil && !fallback.targetVisible)")
    guard let rendered=privateFrame.image, privateFrame.targetVisible, let blurred=fallback.image, !fallback.targetVisible,let face=result.faceBox else {exit(1)}
    let center=CGRect(x:face.x+face.width*0.25,y:1-face.y-face.height*0.75,width:face.width*0.5,height:face.height*0.5)
    guard verifyPrivacy(source:source,processed:rendered,target:center,background:CGRect(x:0.02,y:0.05,width:0.18,height:0.85)),
          edgeEnergy(blurred,box:center)/max(0.001,edgeEnergy(source,box:center)) < 0.25 else {exit(1)}
}
print("faces=\(result.faces) bodies=\(result.bodies) target=\(result.status.rawValue) head=\(result.metrics?.headPitch != nil) lateral=\(result.metrics?.lateral != nil) shoulders=\(result.metrics?.shoulderTilt != nil) shrug=\(result.metrics?[.shrug] != nil) headForward=\(result.metrics?[.headForward] != nil)")
print(result.reason)
guard result.metrics?.headPitch != nil, let box=result.faceBox else { exit(1) }
if args.contains("--require-shoulders"), (result.metrics?.lateral == nil || result.metrics?.shoulderTilt == nil) { exit(1) }
if args.contains("--require-shrug"), result.metrics?[.shrug] == nil {exit(1)}
if args.contains("--require-head-forward"), result.metrics?[.headForward] == nil {exit(1)}
if args.contains("--multi") {
    // A deterministic additional small face is composited in memory only, to exercise Vision + selection.
    let faceRect=CGRect(x:box.x*Double(source.width),y:(1-box.y-box.height)*Double(source.height),width:box.width*Double(source.width),height:box.height*Double(source.height))
    guard let patch=source.cropping(to:faceRect), let ctx=CGContext(data:nil,width:source.width,height:source.height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(2) }
    ctx.draw(source,in:CGRect(x:0,y:0,width:source.width,height:source.height))
    ctx.draw(patch,in:CGRect(x:Double(source.width)*0.06,y:Double(source.height)*0.58,width:Double(source.width)*0.09,height:Double(source.height)*0.16))
    guard let composite=ctx.makeImage() else { exit(2) }
    let multi=try analyze(composite,now:0.2)
    print("multi faces=\(multi.faces) target=\(multi.status.rawValue) head=\(multi.metrics?.headPitch != nil) lateral=\(multi.metrics?.lateral != nil) shoulders=\(multi.metrics?.shoulderTilt != nil)")
    guard multi.faces >= 2, multi.status == .locked, let newBox=multi.faceBox, abs(newBox.center.x-box.center.x) < 0.03, multi.metrics?.headPitch != nil else { exit(1) }
    if args.contains("--require-shoulders"), (multi.metrics?.lateral == nil || multi.metrics?.shoulderTilt == nil) { exit(1) }
    if args.contains("--require-shrug"), multi.metrics?[.shrug] == nil {exit(1)}
    if args.contains("--require-head-forward"), multi.metrics?[.headForward] == nil {exit(1)}
    if args.contains("--privacy") {
        let privacy = PrivacyCompositor().render(image:composite,target:multi.faceBox,detectedFaces:args.contains("--independent-faces") ? nil : multi.faceBoxes)
        print("multi privacy target=\(privacy.targetVisible) excludedFaces=\(privacy.excludedFaces)")
        guard privacy.targetVisible, privacy.excludedFaces >= 1,let rendered=privacy.image else {exit(1)}
        let patchBox=CGRect(x:0.06,y:1-0.58-0.16,width:0.09,height:0.16)
        guard edgeEnergy(rendered,box:patchBox)/max(0.001,edgeEnergy(composite,box:patchBox)) < 0.25 else {exit(1)}
    }
    print("PASS: foreground stays locked with an additional background-sized face")
}
