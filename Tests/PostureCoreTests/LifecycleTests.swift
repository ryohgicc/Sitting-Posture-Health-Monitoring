import XCTest
@testable import PostureCore

final class LifecycleTests: XCTestCase {
    func testGenerationRejectsOldStartAndAcceptsLatest() {
        let gate = GenerationGate()
        let old = gate.advance(); let newest = gate.advance()
        XCTAssertFalse(gate.accepts(old)); XCTAssertTrue(gate.accepts(newest))
    }
    func testWatchdogIncludesTimeBeforeFirstFrame() {
        var watch = FrameWatchdog()
        watch.start(now: 100)
        XCTAssertFalse(watch.expired(now: 109))
        XCTAssertTrue(watch.expired(now: 111))
        watch.received(now: 111)
        XCTAssertFalse(watch.expired(now: 112))
        watch.stop()
        XCTAssertFalse(watch.expired(now: 1000))
    }
    func testReminderAggregatorMergesAndDeliversAtMostOncePerMinute() {
        var a = ReminderAggregator()
        a.enqueue("姿态", now: 0)
        a.enqueue("活动", now: 0.5)
        XCTAssertNil(a.take(now: 0.7))
        XCTAssertEqual(a.take(now: 1.6), ["姿态", "活动"])
        a.enqueue("新指标", now: 10)
        XCTAssertNil(a.take(now: 11))
        XCTAssertEqual(a.take(now: 62), ["新指标"])
    }
    func testSnoozeDropsPendingReminder() {
        var a = ReminderAggregator()
        a.enqueue("过期姿态", now: 0)
        a.clearPending()
        XCTAssertNil(a.take(now: 200))
    }
    func testShouldersRemainMeasurableWithoutHead() {
        let g = FrameGeometry(leftShoulder: Point2(x: 100,y: 200), rightShoulder: Point2(x: 300,y: 220), head: nil)
        XCTAssertNotNil(g.shoulderTilt)
        XCTAssertNil(g.lateral)
    }
    func testPartialCalibrationDoesNotBlockAvailableShoulders() {
        var c = CalibrationAccumulator()
        for i in 0...50 { c.add(PoseMetrics(headPitch: nil,lateral: nil,shoulderTilt: 0.1), now: Double(i)*0.2) }
        let b = c.result(now: 10)
        XCTAssertNotNil(b?.shoulderTilt)
        XCTAssertNil(b?.headPitch)
    }
    func testUnstableOneMetricDoesNotDestroyOtherCalibration() {
        var c = CalibrationAccumulator()
        for i in 0...50 { c.add(PoseMetrics(headPitch: i % 2 == 0 ? -0.4 : 0.4,lateral: 0,shoulderTilt: 0), now: Double(i)*0.2) }
        XCTAssertNil(c.result(now: 10)?.headPitch)
        XCTAssertNotNil(c.result(now: 10)?.shoulderTilt)
    }
}

extension LifecycleTests {
    func testSuddenScaleJumpRequiresStableReentry() {
        var guarder = ScaleContinuity()
        XCTAssertTrue(guarder.accept(width: 200, now: 0))
        XCTAssertTrue(guarder.accept(width: 205, now: 0.2))
        XCTAssertFalse(guarder.accept(width: 400, now: 0.4))
        XCTAssertFalse(guarder.accept(width: 401, now: 1))
        XCTAssertTrue(guarder.accept(width: 400, now: 3.5))
        XCTAssertFalse(guarder.accept(width: .nan, now: 4))
    }
}

extension LifecycleTests {
    func testResolvedPostureCancelsQueuedAlertWithoutDroppingActivity() {
        var a = ReminderAggregator()
        a.enqueue("旧姿态", channel: "posture", now: 0)
        a.enqueue("活动", channel: "activity", now: 0.2)
        a.cancel(channel: "posture")
        XCTAssertEqual(a.take(now: 2), ["活动"])
    }
    func testNewPostureReplacesQueuedOldPosture() {
        var a = ReminderAggregator()
        a.enqueue("旧姿态", channel: "posture", now: 0)
        a.enqueue("当前姿态", channel: "posture", now: 0.2)
        XCTAssertEqual(a.take(now: 2), ["当前姿态"])
    }
    func testManualActivityResetCancelsPendingActivity() {
        var a = ReminderAggregator()
        a.enqueue("活动", channel: "activity", now: 0)
        a.cancel(channel: "activity")
        XCTAssertNil(a.take(now: 2))
    }
}
