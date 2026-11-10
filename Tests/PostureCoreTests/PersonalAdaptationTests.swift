import XCTest
@testable import PostureCore

final class PersonalAdaptationTests: XCTestCase {
    private let zero = PoseMetrics(headPitch:0,lateral:0,shoulderTilt:0)
    private func reference(_ s: inout AdaptationSession, partial: Bool = false) {
        for n in 0...60 { s.update(PoseMetrics(headPitch:0,lateral:partial ? nil : 0,shoulderTilt:partial ? nil : 0),now:Double(n)*0.2) }
    }
    private func hold(_ s: inout AdaptationSession, _ m: PoseMetrics, at: Double) {
        for n in 0...15 { s.update(m,now:at+Double(n)*0.2) }
    }
    func testReferenceThenNaturalActionsAndExplicitReview() throws {
        var s=AdaptationSession(preferences:Preferences())
        reference(&s)
        XCTAssertEqual(s.step,.headDown)
        hold(&s,PoseMetrics(headPitch:0.15,lateral:0,shoulderTilt:0),at:13)
        XCTAssertTrue(s.record())
        hold(&s,PoseMetrics(headPitch:0,lateral:0.12,shoulderTilt:0),at:17)
        XCTAssertTrue(s.record())
        hold(&s,PoseMetrics(headPitch:0,lateral:-0.16,shoulderTilt:0),at:21)
        XCTAssertTrue(s.record())
        hold(&s,PoseMetrics(headPitch:0,lateral:0,shoulderTilt:0.1),at:25)
        XCTAssertTrue(s.record())
        s.skip(); s.skip() // Optional bilateral shoulder and head approach steps.
        XCTAssertEqual(s.step,.experience)
        let p=try XCTUnwrap(s.profile)
        XCTAssertEqual(p.threshold(for:.headDown),0.15,accuracy:0.001)
        XCTAssertEqual(p.threshold(for:.lean),0.12,accuracy:0.001)
        XCTAssertEqual(p.threshold(for:.shoulders),0.1,accuracy:0.001)
        hold(&s,PoseMetrics(headPitch:0.3,lateral:0,shoulderTilt:0),at:29)
        hold(&s,PoseMetrics(headPitch:0.3,lateral:0,shoulderTilt:0),at:32.2)
        XCTAssertEqual(s.readings[.headDown]?.phase,.active)
        for n in 0...60 {s.update(zero,now:35.4+Double(n)*0.2)}
        XCTAssertEqual(s.readings[.headDown]?.phase,.below)
        s.review()
        XCTAssertEqual(s.step,.review)
    }
    func testRejectsLookingUpWrongSecondDirectionAndMissingMetric() {
        var s=AdaptationSession(preferences:Preferences()); reference(&s)
        hold(&s,PoseMetrics(headPitch:-0.3,lateral:0,shoulderTilt:0),at:13)
        XCTAssertFalse(s.record()); XCTAssertEqual(s.step,.headDown)
        s.skip()
        hold(&s,PoseMetrics(headPitch:0,lateral:0.2,shoulderTilt:0),at:17); XCTAssertTrue(s.record())
        hold(&s,PoseMetrics(headPitch:0,lateral:0.25,shoulderTilt:0),at:21)
        XCTAssertFalse(s.record()); XCTAssertEqual(s.step,.leanOther)
        s.update(nil,now:24.2); XCTAssertEqual(s.actionProgress,0)
        XCTAssertFalse(s.record())
        s.skip(); s.skip()
        XCTAssertNil(s.profile?.thresholds[.lean])
    }
    func testPartialReferenceSkipsUnavailableWithoutLearningAndGapResets() {
        var s=AdaptationSession(preferences:Preferences()); reference(&s,partial:true)
        hold(&s,PoseMetrics(headPitch:0.2,lateral:nil,shoulderTilt:nil),at:13)
        s.update(zero,now:20)
        XCTAssertFalse(s.record())
        s.skip(); s.skip(); s.skip(); s.skip(); s.skip()
        XCTAssertEqual(s.step,.experience)
        XCTAssertTrue(s.profile?.thresholds.isEmpty == true)
        XCTAssertEqual(s.profile?.threshold(for:.lean),Issue.lean.threshold)
    }
    func testNoiseAndUnstableActionDoNotBecomeLearnedBoundary() {
        var s=AdaptationSession(preferences:Preferences())
        for n in 0...60 {s.update(PoseMetrics(headPitch:n%2 == 0 ? 0.2 : -0.2,lateral:nil,shoulderTilt:nil),now:Double(n)*0.2)}
        XCTAssertEqual(s.step,.reference)
        s=AdaptationSession(preferences:Preferences()); reference(&s)
        for n in 0...15 {s.update(PoseMetrics(headPitch:n%2 == 0 ? 0.4 : 0.1,lateral:0,shoulderTilt:0),now:13+Double(n)*0.2)}
        XCTAssertFalse(s.record())
    }
    func testProfileValidationBoundsRoundTripAndActualJudgeThreshold() throws {
        let p=PersonalProfile(baseline:zero,thresholds:[.headDown:0.12])
        XCTAssertNotNil(p.validated)
        let roundTrip=try JSONDecoder().decode(PersonalProfile.self,from:JSONEncoder().encode(p))
        XCTAssertEqual(roundTrip.threshold(for:.headDown,sensitivity:1.4),0.168,accuracy:0.0001)
        XCTAssertNil(PersonalProfile(baseline:zero,thresholds:[.headDown:.nan]).validated)
        XCTAssertNil(PersonalProfile(baseline:zero,thresholds:[.headDown:99]).validated)
        XCTAssertFalse(p.matches(PoseMetrics(headPitch:0.01,lateral:0,shoulderTilt:0)))
        var judge=PostureJudge(baseline:zero,preferences:Preferences(),smoothing:false,profile:p)
        var v=judge.update(PoseMetrics(headPitch:0.15,lateral:0,shoulderTilt:0),now:0)
        XCTAssertEqual(v.readings[.headDown]?.threshold,0.12)
        v=judge.update(PoseMetrics(headPitch:0.15,lateral:0,shoulderTilt:0),now:2)
        _=judge.update(PoseMetrics(headPitch:0.15,lateral:0,shoulderTilt:0),now:4)
        v=judge.update(PoseMetrics(headPitch:0.15,lateral:0,shoulderTilt:0),now:5)
        XCTAssertTrue(v.alerts.contains(.headDown))
    }
    func testMissingMetricClearsLiveReadingAndRequiresFreshHold() {
        var s=AdaptationSession(preferences:Preferences()); reference(&s)
        hold(&s,PoseMetrics(headPitch:0.2,lateral:0,shoulderTilt:0),at:13)
        XCTAssertNotNil(s.readings[.headDown])
        s.update(PoseMetrics(headPitch:nil,lateral:0,shoulderTilt:0),now:16.2)
        XCTAssertNil(s.readings[.headDown])
        XCTAssertFalse(s.record())
        XCTAssertEqual(s.actionProgress,0)
    }
    func testSkippingEitherLateralTrialSkipsEntireLateralLearning() {
        var s=AdaptationSession(preferences:Preferences()); reference(&s)
        s.skip(); s.skip()
        XCTAssertEqual(s.step,.shoulders)
        XCTAssertNil(s.profile?.thresholds[.lean])
    }
    func testRecordingRejectionDistinguishesDirectionNoiseAndSmallChange() throws {
        var s=AdaptationSession(preferences:Preferences()); reference(&s)
        hold(&s,PoseMetrics(headPitch:-0.2,lateral:0,shoulderTilt:0),at:13)
        XCTAssertFalse(s.record())
        let direction=try XCTUnwrap(s.recordFeedback)
        hold(&s,PoseMetrics(headPitch:0.01,lateral:0,shoulderTilt:0),at:17)
        XCTAssertFalse(s.record())
        let small=try XCTUnwrap(s.recordFeedback)
        XCTAssertNotEqual(direction,small)
        for n in 0...15 {s.update(PoseMetrics(headPitch:n%2 == 0 ? 0.08 : 0.20,lateral:0,shoulderTilt:0),now:21+Double(n)*0.2)}
        XCTAssertFalse(s.record())
        XCTAssertNotEqual(s.recordFeedback,small)
        s.skip();XCTAssertNil(s.recordFeedback)
    }
    func testAdjustmentsAreBoundedAndResetExperienceTimers() {
        var s=AdaptationSession(preferences:Preferences()); reference(&s)
        for _ in 0..<5 {s.skip()}
        hold(&s,PoseMetrics(headPitch:0.4,lateral:0,shoulderTilt:0),at:13)
        s.adjust(.headDown,factor:1.15)
        XCTAssertTrue(s.readings.isEmpty)
        XCTAssertEqual(s.profile?.threshold(for:.headDown) ?? 0,0.23,accuracy:0.001)
        for _ in 0..<50 {s.adjust(.headDown,factor:1.15)}
        XCTAssertEqual(s.profile?.threshold(for:.headDown) ?? 0,0.36,accuracy:0.001)
    }
}
