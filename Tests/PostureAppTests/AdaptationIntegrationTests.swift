import XCTest
import Combine
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
            let time=100.0
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
    func testNewShrugToggleMigratesOnceAndOffSurvivesRestart() async {
        await MainActor.run {
            let name="local.posturepal.tests.\(UUID().uuidString)";let defaults=UserDefaults(suiteName:name)!
            defer {defaults.removePersistentDomain(forName:name)}
            defaults.set(["headDown","shoulders"],forKey:"enabled.v1")
            let model=AppModel(defaults:defaults,notificationCenter:nil);defer {model.shutdown()}
            XCTAssertTrue(model.enabled.contains(.shrug))
            XCTAssertFalse(model.enabled.contains(.lean))
            model.enabled.remove(.shrug);model.save()
            let reopened=AppModel(defaults:defaults,notificationCenter:nil);defer {reopened.shutdown()}
            XCTAssertFalse(reopened.enabled.contains(.shrug))
            XCTAssertFalse(reopened.enabled.contains(.lean))
        }
    }
    func testHeadForwardToggleAddedWithoutChangingOldChoicesAndOffPersists() async {
        await MainActor.run {
            let name="local.posturepal.tests.\(UUID().uuidString)"; let defaults=UserDefaults(suiteName:name)!
            defer {defaults.removePersistentDomain(forName:name)}
            defaults.set(["headDown"],forKey:"enabled.v1")
            defaults.set(true,forKey:"shrugEnabledMigrated.v1")
            let model=AppModel(defaults:defaults,notificationCenter:nil);defer {model.shutdown()}
            XCTAssertTrue(model.enabled.contains(.headForward))
            XCTAssertFalse(model.enabled.contains(.shrug));XCTAssertFalse(model.enabled.contains(.lean))
            model.enabled.remove(.headForward);model.save()
            let reopened=AppModel(defaults:defaults,notificationCenter:nil);defer {reopened.shutdown()}
            XCTAssertFalse(reopened.enabled.contains(.headForward))
            XCTAssertEqual(reopened.enabled,[.headDown])
        }
    }
    func testRecordAdaptationPublishesUpdatedStepToSwiftUI() async throws {
        try await MainActor.run {
            let name="local.posturepal.tests.\(UUID().uuidString)"; let defaults=UserDefaults(suiteName:name)!
            defer {defaults.removePersistentDomain(forName:name)}
            var now=100.0
            let model=AppModel(defaults:defaults,notificationCenter:nil,time:{now}); defer {model.shutdown()}
            model.requested=true; model.capturing=true
            let zero=PoseMetrics(headPitch:0,lateral:0,shoulderTilt:0)
            model.metrics=zero; model.subjectBox=SubjectBox(x:0.3,y:0.3,width:0.2,height:0.2)
            model.startAdaptation()
            for n in 0...60 {
                now=100+Double(n)*0.2
                model.consume(CaptureFrame(metrics:zero,points:[],reason:"参考",timestamp:now))
            }
            XCTAssertEqual(model.adaptation?.step,.headDown)
            var updates=0
            let subscription=model.$adaptation.sink { _ in updates += 1 }
            for n in 0...15 {
                now=113+Double(n)*0.2
                model.consume(CaptureFrame(metrics:PoseMetrics(headPitch:0.14,lateral:0,shoulderTilt:0),points:[],reason:"低头",timestamp:now))
            }
            XCTAssertEqual(model.adaptation?.step,.headDown)
            let beforeRecord=updates
            model.recordAdaptation()
            XCTAssertEqual(model.adaptation?.step,.leanFirst)
            XCTAssertEqual(model.adaptation?.profile?.thresholds[.headDown] ?? 0,0.14,accuracy:0.001)
            XCTAssertGreaterThan(updates,beforeRecord)
            _=subscription
        }
    }
    func testRejectedRecordingReasonSurvivesNextCameraFrames() async throws {
        try await MainActor.run {
            let name="local.posturepal.tests.\(UUID().uuidString)"; let defaults=UserDefaults(suiteName:name)!
            defer {defaults.removePersistentDomain(forName:name)}
            var now=100.0
            let model=AppModel(defaults:defaults,notificationCenter:nil,time:{now}); defer {model.shutdown()}
            model.requested=true; model.capturing=true
            let zero=PoseMetrics(headPitch:0,lateral:0,shoulderTilt:0)
            model.metrics=zero; model.subjectBox=SubjectBox(x:0.3,y:0.3,width:0.2,height:0.2)
            model.startAdaptation()
            for n in 0...60 {
                now=100+Double(n)*0.2
                model.consume(CaptureFrame(metrics:zero,points:[],reason:"参考",timestamp:now))
            }
            for n in 0...15 {
                now=113+Double(n)*0.2
                model.consume(CaptureFrame(metrics:PoseMetrics(headPitch:n%2 == 0 ? 0.08 : 0.20,lateral:0,shoulderTilt:0),points:[],reason:"低头",timestamp:now))
            }
            XCTAssertEqual(model.adaptation?.actionProgress,1)
            model.recordAdaptation()
            XCTAssertEqual(model.adaptation?.step,.headDown)
            let rejection=try XCTUnwrap(model.adaptation?.recordFeedback)
            XCTAssertFalse(rejection.isEmpty)
            for n in 1...5 {
                now=116+Double(n)*0.2
                model.consume(CaptureFrame(metrics:PoseMetrics(headPitch:0.14,lateral:0,shoulderTilt:0),points:[],reason:"低头",timestamp:now))
                XCTAssertEqual(model.adaptation?.recordFeedback,rejection)
            }
            for n in 6...25 {
                now=116+Double(n)*0.2
                model.consume(CaptureFrame(metrics:PoseMetrics(headPitch:0.14,lateral:0,shoulderTilt:0),points:[],reason:"低头",timestamp:now))
            }
            model.recordAdaptation()
            XCTAssertEqual(model.adaptation?.step,.leanFirst)
            XCTAssertNil(model.adaptation?.recordFeedback)
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
