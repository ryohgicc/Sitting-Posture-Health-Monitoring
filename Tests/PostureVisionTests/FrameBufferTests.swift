import XCTest
import CoreGraphics
@testable import PostureVision

final class FrameBufferTests: XCTestCase {
    private func source(width:Int,height:Int,color:CGColor) throws -> CGImage {
        let ctx=try XCTUnwrap(CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        let rgba=try XCTUnwrap(color.components)
        ctx.setFillColor(CGColor(colorSpace:CGColorSpaceCreateDeviceRGB(),components:rgba)!);ctx.fill(CGRect(x:0,y:0,width:width,height:height));return try XCTUnwrap(ctx.makeImage())
    }
    func testReusedRGBAReplacesPreviousFrameIncludingTransparentPixels() throws {
        let buffer=RGBAFrameBuffer()
        let red=try source(width:8,height:4,color:CGColor(red:1,green:0,blue:0,alpha:1))
        let clear=try source(width:8,height:4,color:CGColor(red:0,green:0,blue:0,alpha:0))
        XCTAssertTrue(buffer.draw(red))
        XCTAssertEqual(buffer.bytes.count,128)
        XCTAssertEqual(Array(buffer.bytes.prefix(4)),[255,0,0,255])
        let first=buffer.bytes.baseAddress
        XCTAssertTrue(buffer.draw(clear))
        XCTAssertEqual(first,buffer.bytes.baseAddress)
        XCTAssertTrue(buffer.bytes.allSatisfy {$0 == 0})
    }
    func testResolutionChangeReallocatesAndRendersNewFrame() throws {
        let buffer=RGBAFrameBuffer()
        XCTAssertTrue(buffer.draw(try source(width:8,height:4,color:CGColor(red:1,green:0,blue:0,alpha:1))))
        XCTAssertTrue(buffer.draw(try source(width:16,height:8,color:CGColor(red:0,green:0,blue:1,alpha:1))))
        XCTAssertEqual(buffer.bytes.count,512)
        XCTAssertEqual(Array(buffer.bytes.prefix(4)),[0,0,255,255])
        buffer.clear()
        XCTAssertTrue(buffer.bytes.allSatisfy {$0 == 0})
    }
}
