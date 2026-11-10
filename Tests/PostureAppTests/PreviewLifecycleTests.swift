import XCTest
import CoreGraphics
import PostureCore
@testable import PosturePal

final class PreviewLifecycleTests: XCTestCase {
    func testPreviewDemandRequiresVisibleWindowDashboardAndUserChoice() async {
        await MainActor.run {
            let name="local.posturepal.tests.\(UUID().uuidString)";let defaults=UserDefaults(suiteName:name)!
            defer {defaults.removePersistentDomain(forName:name)}
            let model=AppModel(defaults:defaults,notificationCenter:nil);defer {model.shutdown()}
            XCTAssertFalse(model.previewProcessingEnabled)
            model.setWindowVisible(true);XCTAssertTrue(model.previewProcessingEnabled)
            model.setDashboardVisible(false);XCTAssertFalse(model.previewProcessingEnabled)
            model.setDashboardVisible(true);XCTAssertTrue(model.previewProcessingEnabled)
            model.showPreview=false;model.setWindowVisible(false);model.setWindowVisible(true)
            XCTAssertFalse(model.previewProcessingEnabled);XCTAssertFalse(model.showPreview)
        }
    }
    func testHiddenWindowRejectsLatePreviewButJudgementKeepsRunning() async throws {
        try await MainActor.run {
            let name="local.posturepal.tests.\(UUID().uuidString)";let defaults=UserDefaults(suiteName:name)!
            defer {defaults.removePersistentDomain(forName:name)}
            let baseline=PoseMetrics(headPitch:0,lateral:0,shoulderTilt:0)
            defaults.set(try JSONEncoder().encode(baseline),forKey:"baseline.v1")
            var time=100.0
            let model=AppModel(defaults:defaults,notificationCenter:nil,time:{time});defer {model.shutdown()}
            model.setWindowVisible(true);model.capturing=true;model.requested=true
            let oldRevision=model.camera.setPreviewEnabled(true)
            let ctx=try XCTUnwrap(CGContext(data:nil,width:8,height:8,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            let image=try XCTUnwrap(ctx.makeImage())
            model.previewImage=image;model.previewTargetVisible=true;model.points=[CGPoint(x:0.2,y:0.4)]
            model.setWindowVisible(false)
            XCTAssertNil(model.previewImage);XCTAssertTrue(model.points.isEmpty)
            for t in 0...8 {
                time=100+Double(t)
                model.consume(CaptureFrame(previewImage:image,previewTargetVisible:true,previewRevision:0,metrics:PoseMetrics(headPitch:0.4,lateral:0,shoulderTilt:0),points:[CGPoint(x:0.2,y:0.4)],reason:"有效",timestamp:time))
            }
            XCTAssertNil(model.previewImage);XCTAssertFalse(model.previewTargetVisible);XCTAssertTrue(model.points.isEmpty)
            XCTAssertTrue(model.active.contains(.headDown))
            XCTAssertNotNil(model.readings[.headDown])
            model.setWindowVisible(true)
            time += 0.2
            model.consume(CaptureFrame(previewImage:image,previewTargetVisible:true,previewRevision:oldRevision,metrics:baseline,points:[],reason:"旧帧",timestamp:time))
            XCTAssertNil(model.previewImage)
            let currentRevision=model.camera.setPreviewEnabled(true)
            time += 0.2
            model.consume(CaptureFrame(previewImage:image,previewTargetVisible:true,previewRevision:currentRevision,metrics:baseline,points:[],reason:"新帧",timestamp:time))
            XCTAssertTrue(model.previewImage === image)
        }
    }
    func testPreviewVisibilityRevisionRejectsPriorFrameWhenReopened() async {
        await MainActor.run {
            let pipeline=CameraPipeline()
            let visible=pipeline.setPreviewEnabled(true)
            let hidden=pipeline.setPreviewEnabled(false)
            let reopened=pipeline.setPreviewEnabled(true)
            XCTAssertNotEqual(visible,hidden);XCTAssertNotEqual(hidden,reopened)
            XCTAssertEqual(reopened,pipeline.setPreviewEnabled(true))
        }
    }
}
