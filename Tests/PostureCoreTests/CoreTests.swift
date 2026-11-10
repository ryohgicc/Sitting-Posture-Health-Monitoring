import XCTest
@testable import PostureCore

final class CoreTests: XCTestCase {
    let baseline = PoseMetrics(headPitch: 0, lateral: 0, shoulderTilt: 0)
    let down = PoseMetrics(headPitch: 0.3, lateral: 0, shoulderTilt: 0)

    func testCalibrationRequiresDurationCoverageAndStability() {
        var c = CalibrationAccumulator()
        for i in 0..<50 { c.add(baseline, now: Double(i) * 0.2) }
        XCTAssertNil(c.result(now: 9.8))
        c.add(baseline, now: 10)
        XCTAssertNotNil(c.result(now: 10))
        var sparse = CalibrationAccumulator()
        sparse.add(baseline, now: 0); sparse.add(baseline, now: 10)
        XCTAssertNil(sparse.result(now: 10))
        var moving = CalibrationAccumulator()
        for i in 0...50 { moving.add(PoseMetrics(headPitch: i % 2 == 0 ? -0.4 : 0.4, lateral: 0, shoulderTilt: 0), now: Double(i) * 0.2) }
        XCTAssertNil(moving.result(now: 10)?.headPitch)
    }

    func testDwellRecoveryAndPerTypeCooldown() {
        var j = PostureJudge(baseline: baseline, smoothing: false)
        for t in 0..<20 { XCTAssertTrue(j.update(down, now: Double(t)).alerts.isEmpty) }
        XCTAssertEqual(j.update(down, now: 20).alerts, [.headDown])
        XCTAssertTrue(j.update(down, now: 21).alerts.isEmpty)
        _ = j.update(baseline, now: 22)
        XCTAssertTrue(j.update(baseline, now: 25).active.isEmpty)
        for t in 26...47 { XCTAssertTrue(j.update(down, now: Double(t)).alerts.isEmpty) }
    }

    func testMissingMetricResetsOnlyItsOwnPendingDwell() {
        var j = PostureJudge(baseline: baseline, smoothing: false)
        for t in 0...15 { _ = j.update(down, now: Double(t)) }
        _ = j.update(PoseMetrics(headPitch: nil, lateral: 0.5, shoulderTilt: 0), now: 16)
        for t in 17...35 { XCTAssertTrue(j.update(down, now: Double(t)).alerts.isEmpty) }
        XCTAssertEqual(j.update(down, now: 37).alerts, [.headDown])
    }

    func testLongFrameGapDoesNotCountTowardDwell() {
        var j = PostureJudge(baseline: baseline, smoothing: false)
        _ = j.update(down, now: 0)
        XCTAssertTrue(j.update(down, now: 60).alerts.isEmpty)
    }

    func testSnoozeDiscardsStaleDwell() {
        var j = PostureJudge(baseline: baseline, smoothing: false)
        for t in 0...19 { _ = j.update(down, now: Double(t), muted: true) }
        XCTAssertTrue(j.update(down, now: 20, muted: false).alerts.isEmpty)
    }

    func testGeometryUsesPixelsAndRejectsOccludedOrTurnedShoulders() {
        let points = FrameGeometry(leftShoulder: Point2(x: 100, y: 200), rightShoulder: Point2(x: 300, y: 200), head: Point2(x: 200, y: 100))
        XCTAssertEqual(points.lateral!, 0, accuracy: 0.0001)
        XCTAssertEqual(points.shoulderTilt!, 0, accuracy: 0.0001)
        XCTAssertNil(FrameGeometry(leftShoulder: Point2(x: 0, y: 0), rightShoulder: Point2(x: 1, y: 0), head: Point2(x: 0, y: 1)).lateral)
    }

    func testActivityClockPauseAndReset() {
        var c = SessionClock(interval: 2700)
        XCTAssertFalse(c.tick(now: 0, running: true, muted: false))
        XCTAssertFalse(c.tick(now: 100, running: true, muted: false)) // long gap excluded
        for t in 101...200 { _ = c.tick(now: Double(t), running: true, muted: false) }
        XCTAssertEqual(c.elapsed, 100)
        _ = c.tick(now: 201, running: false, muted: false)
        _ = c.tick(now: 202, running: true, muted: false)
        XCTAssertEqual(c.elapsed, 100)
        c.reset(now: 202)
        XCTAssertEqual(c.elapsed, 0)
    }

    func testPreferencesClampCorruptedValues() {
        let p = Preferences(dwell: -1, cooldown: .nan, sensitivity: 100, activityInterval: -20)
        XCTAssertEqual(p.dwell, 20)
        XCTAssertEqual(p.cooldown, 600)
        XCTAssertEqual(p.sensitivity, 1)
        XCTAssertEqual(p.activityInterval, 2700)
    }
}

extension CoreTests {
    func testHeadDownDoesNotClassifyLookingUpAsDown() {
        var j = PostureJudge(baseline: baseline, smoothing: false)
        let up = PoseMetrics(headPitch: -0.4, lateral: 0, shoulderTilt: 0)
        for t in 0...25 { XCTAssertTrue(j.update(up, now: Double(t)).active.isEmpty) }
    }
    func testCorruptedDecodedBaselineCannotCalibrateJudge() {
        let bad = PoseMetrics(headPitch: nil, lateral: .nan, shoulderTilt: .infinity)
        XCTAssertFalse(bad.complete)
        var c = CalibrationAccumulator()
        for t in 0...50 { c.add(bad, now: Double(t)*0.2) }
        XCTAssertNil(c.result(now: 10))
    }
    func testSimultaneousAlertsMergeAndNewTypeWaitsSixtySeconds() {
        var j = PostureJudge(baseline: baseline, smoothing: false)
        for t in 0...19 { _ = j.update(down, now: Double(t)) }
        XCTAssertEqual(j.update(down, now: 20).alerts, [.headDown])
        let both = PoseMetrics(headPitch: 0.3, lateral: 0.5, shoulderTilt: 0)
        for t in 21..<80 { XCTAssertTrue(j.update(both, now: Double(t)).alerts.isEmpty) }
        XCTAssertEqual(j.update(both, now: 80).alerts, [.lean])
    }
    func testDisabledMetricAndFrameLossDoNotReportGoodOrActive() {
        var j = PostureJudge(baseline: baseline, smoothing: false)
        for t in 0...20 { _ = j.update(down, now: Double(t)) }
        j.enabled.remove(.headDown)
        XCTAssertTrue(j.update(down, now: 21).active.isEmpty)
        XCTAssertNil(j.update(down, now: 22).deviations[.headDown])
        XCTAssertTrue(j.update(nil, now: 23).deviations.isEmpty)
    }
    func testMutedActivityReminderIsNotQueuedAfterSnooze() {
        var c = SessionClock(interval: 3)
        _ = c.tick(now: 0, running: true, muted: true)
        for t in 1...3 { XCTAssertFalse(c.tick(now: Double(t), running: true, muted: true)) }
        XCTAssertFalse(c.tick(now: 4, running: true, muted: false))
        c.reset(now: 4)
        for t in 5...6 { XCTAssertFalse(c.tick(now: Double(t), running: true, muted: false)) }
        XCTAssertTrue(c.tick(now: 7, running: true, muted: false))
    }
}
