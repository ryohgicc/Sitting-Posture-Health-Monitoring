import XCTest
import CoreGraphics
import PostureCore
import PostureVision

final class FaceBlurTests: XCTestCase {
    // A raw fallback, a missed second face, or a flipped mask leaves checker detail intact.
    func testFaceBlurObscuresAllFacesWithoutBlurringTheWholePreview() throws {
        let image=try checkerImage()
        let faces=[SubjectBox(x:0.08,y:0.1,width:0.18,height:0.25),SubjectBox(x:0.72,y:0.65,width:0.18,height:0.25)]
        let result=PrivacyCompositor().render(image:image,target:faces[0],blurEnabled:false,faceBlurEnabled:true,detectedFaces:faces)
        let output=try XCTUnwrap(result.image)
        XCTAssertLessThan(try detail(output,x:30..<65,y:140..<170),try detail(image,x:30..<65,y:140..<170)*0.2)
        XCTAssertLessThan(try detail(output,x:225..<260,y:20..<50),try detail(image,x:225..<260,y:20..<50)*0.2)
        XCTAssertEqual(try detail(output,x:135..<165,y:80..<120),try detail(image,x:135..<165,y:80..<120),accuracy:1)
    }
    func testNoUsableFacesUsesFullBlurInsteadOfRawFallback() throws {
        let image=try checkerImage()
        for faces in [[],[SubjectBox(x:Double.nan,y:0.3,width:0.2,height:0.3)]] {
            let result=PrivacyCompositor().render(image:image,target:nil,blurEnabled:false,faceBlurEnabled:true,detectedFaces:faces)
            let output=try XCTUnwrap(result.image)
            XCTAssertFalse(output === image)
            XCTAssertLessThan(try detail(output,x:135..<165,y:80..<120),try detail(image,x:135..<165,y:80..<120)*0.2)
        }
    }
    func testFaceBlurRemainsActiveWithBackgroundBlurEnabled() throws {
        let image=try checkerImage()
        let result=PrivacyCompositor().render(image:image,target:nil,blurEnabled:true,faceBlurEnabled:true,detectedFaces:[])
        let output=try XCTUnwrap(result.image)
        XCTAssertLessThan(try detail(output,x:135..<165,y:80..<120),try detail(image,x:135..<165,y:80..<120)*0.2)
    }
    private func checkerImage() throws -> CGImage {
        let ctx=try XCTUnwrap(CGContext(data:nil,width:300,height:200,bitsPerComponent:8,bytesPerRow:1200,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        for y in stride(from:0,to:200,by:2) {
            for x in stride(from:0,to:300,by:2) {
                ctx.setFillColor(((x/2+y/2)%2 == 0 ? CGColor(gray:1,alpha:1) : CGColor(gray:0,alpha:1)))
                ctx.fill(CGRect(x:x,y:y,width:2,height:2))
            }
        }
        return try XCTUnwrap(ctx.makeImage())
    }
    private func detail(_ image: CGImage,x:Range<Int>,y:Range<Int>) throws -> Double {
        let ctx=try XCTUnwrap(CGContext(data:nil,width:300,height:200,bitsPerComponent:8,bytesPerRow:1200,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image,in:CGRect(x:0,y:0,width:300,height:200))
        let data=try XCTUnwrap(ctx.data).assumingMemoryBound(to:UInt8.self)
        var sum=0.0, count=0.0
        for row in y {for col in x.dropLast() {sum += abs(Double(data[row*1200+col*4])-Double(data[row*1200+(col+1)*4]));count += 1}}
        return sum/count
    }
}
