import XCTest
import CoreGraphics
import PostureVision
import PostureCore

final class PreviewModeTests: XCTestCase {
    func testExplicitOffPassesThroughCameraImage() throws {
        let ctx=try XCTUnwrap(CGContext(data:nil,width:32,height:32,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        let source=try XCTUnwrap(ctx.makeImage())
        let result=PrivacyCompositor().render(image:source,target:nil,blurEnabled:false)
        XCTAssertTrue(result.image === source)
        XCTAssertFalse(result.targetVisible)
    }
    func testDefaultOnNeverFallsBackToSourceWithoutTarget() throws {
        let ctx=try XCTUnwrap(CGContext(data:nil,width:32,height:32,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        let source=try XCTUnwrap(ctx.makeImage())
        let result=PrivacyCompositor().render(image:source,target:nil)
        XCTAssertNotNil(result.image)
        XCTAssertFalse(result.image === source)
        XCTAssertFalse(result.targetVisible)
    }
    func testSuppliedEmptySameFrameFacesRemainPrivateWithTarget() throws {
        let ctx=try XCTUnwrap(CGContext(data:nil,width:32,height:32,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        let source=try XCTUnwrap(ctx.makeImage())
        let target=PostureCore.SubjectBox(x:0.3,y:0.3,width:0.3,height:0.4)
        let result=PrivacyCompositor().render(image:source,target:target,detectedFaces:[])
        XCTAssertNotNil(result.image);XCTAssertFalse(result.image === source);XCTAssertFalse(result.targetVisible)
    }
}
