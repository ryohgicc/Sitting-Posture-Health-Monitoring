import XCTest
import PostureCore
@testable import PosturePal

final class AdaptationIntegrationTests: XCTestCase {
    func testCancelPreservesAcceptedSettingsAndRecalibrationStartDoesNotEraseThem() async throws {
        try await MainActor.run {
            let name="local.posturepal.tests.\(UUID().uuidString)"
            let defaults=UserDefaults(suiteName:name)!
            defer {defaults.removePersistentDomain(forName:name)}
            let baseline=PoseMetrics(headPitch:0,lateral:0,shoulderTilt:0)
            let profile=PersonalProfile(baseline:baseline,thresholds:[.headDown:0.15])
            defaults.set(try JSONEncoder().encode(baseline),forKey:"baseline.v1")
            defaults.set(try JSONEncoder().encode(profile),forKey:"personalProfile.v1")
            var time=100.0
            let model=AppModel(defaults:defaults,notificationCenter:nil,time:{time}); defer {model.shutdown()}
            model.capturing=true; model.metrics=baseline; model.subjectBox=SubjectBox(x:0.3,y:0.3,width:0.2,height:0.2)
            model.startAdaptation(); XCTAssertNotNil(model.adaptation)
            model.cancelAdaptation()
            XCTAssertEqual(model.personalProfile?.threshold(for:.headDown),0.15)
            XCTAssertNotNil(defaults.data(forKey:"personalProfile.v1"))
            model.beginCalibration()
            XCTAssertEqual(model.personalProfile?.threshold(for:.headDown),0.15)
            XCTAssertNotNil(defaults.data(forKey:"personalProfile.v1"))
            model.stop()
            XCTAssertEqual(model.personalProfile?.threshold(for:.headDown),0.15)
        }
    }
    func testSettingsStopAndRelockCancelDraftAndRelockInvalidatesProfile() async {
        await MainActor.run {
            let name="local.posturepal.tests.\(UUID().uuidString)"; let defaults=UserDefaults(suiteName:name)!
            defer {defaults.removePersistentDomain(forName:name)}
            let model=AppModel(defaults:defaults,notificationCenter:nil); defer {model.shutdown()}
            let baseline=PoseMetrics(headPitch:0,lateral:0,shoulderTilt:0)
            model.capturing=true; model.metrics=baseline; model.subjectBox=SubjectBox(x:0.3,y:0.3,width:0.2,height:0.2)
            model.startAdaptation(); model.save(); XCTAssertNil(model.adaptation)
            model.startAdaptation(); model.stop(); XCTAssertNil(model.adaptation)
            model.capturing=true; model.metrics=baseline; model.subjectBox=SubjectBox(x:0.3,y:0.3,width:0.2,height:0.2)
            model.personalProfile=PersonalProfile(baseline:baseline,thresholds:[.headDown:0.15])
            model.startAdaptation(); model.relock(); XCTAssertNil(model.adaptation); XCTAssertNil(model.personalProfile)
        }
    }
    func testResumedInputAfterThreeSecondsCancelsDraft() async {
        await MainActor.run {
            let name="local.posturepal.tests.\(UUID().uuidString)"; let defaults=UserDefaults(suiteName:name)!
            defer {defaults.removePersistentDomain(forName:name)}
            var time=100.0
            let model=AppModel(defaults:defaults,notificationCenter:nil,time:{time});defer {model.shutdown()}
            let zero=PoseMetrics(headPitch:0,lateral:0,shoulderTilt:0)
            model.capturing=true;model.requested=true;model.metrics=zero;model.subjectBox=SubjectBox(x:0.3,y:0.3,width:0.2,height:0.2)
            model.startAdaptation()
            for t in [101.0,102,103] {time=t;model.consume(CaptureFrame(metrics:nil,points:[],reason:"转头",timestamp:t))}
            XCTAssertNotNil(model.adaptation)
            time=103.2;model.consume(CaptureFrame(metrics:zero,points:[],reason:"恢复",timestamp:time))
            XCTAssertNil(model.adaptation)
        }
    }
    func testActivityTimerPausesDuringGuide() async {
        await MainActor.run {
            let name="local.posturepal.tests.\(UUID().uuidString)"; let defaults=UserDefaults(suiteName:name)!
            defer {defaults.removePersistentDomain(forName:name)}
            var time=100.0
            let model=AppModel(defaults:defaults,notificationCenter:nil,time:{time}); defer {model.shutdown()}
            model.capturing=true;model.metrics=PoseMetrics(headPitch:0,lateral:0,shoulderTilt:0)
            model.subjectBox=SubjectBox(x:0.3,y:0.3,width:0.2,height:0.2)
            model.startAdaptation();model.tick();time=102;model.tick()
            XCTAssertEqual(model.activityElapsed,0)
            XCTAssertEqual(model.latestNotice,"尚无提醒")
        }
    }
}
