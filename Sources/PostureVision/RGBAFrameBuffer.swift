import CoreGraphics

/// Serial reusable scratch storage. Clear after inference; never retain a prior frame.
final class RGBAFrameBuffer {
    private var storage: UnsafeMutableRawPointer?
    private var context: CGContext?
    private var width=0, height=0
    var bytes: UnsafeRawBufferPointer {UnsafeRawBufferPointer(start:storage,count:width*height*4)}
    deinit {context=nil;storage?.deallocate()}
    func draw(_ image: CGImage) -> Bool {
        let w=image.width,h=image.height
        guard w > 0, h > 0, w <= 4096, h <= 4096 else {return false}
        if w != width || h != height || context == nil {
            context=nil;storage?.deallocate();storage=nil;width=0;height=0
            let allocation=UnsafeMutableRawPointer.allocate(byteCount:w*h*4,alignment:64)
            guard let created=CGContext(data:allocation,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {allocation.deallocate();return false}
            storage=allocation;context=created;width=w;height=h
        }
        guard let context else {return false}
        context.clear(CGRect(x:0,y:0,width:w,height:h))
        context.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
        return true
    }
    func clear() {context?.clear(CGRect(x:0,y:0,width:width,height:height))}
}
