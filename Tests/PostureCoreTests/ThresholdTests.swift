import XCTest
@testable import PostureCore

final class ThresholdTests: XCTestCase {
    private let base=PoseMetrics(headPitch:0,lateral:0,shoulderTilt:0)
    private func pose(_ pitch:Double) -> PoseMetrics {PoseMetrics(headPitch:pitch,lateral:0,shoulderTilt:0)}
    func testRoundedPercentRetainsWhichSideOfLine() throws {
        for (value, expected) in [(0.19999,"<100%"),(0.20001,">100%"),(0.2,"100%"),(0.15999,"<80%")] {
            var judge=PostureJudge(baseline:base,smoothing:false)
            let reading=try XCTUnwrap(judge.update(pose(value),now:0).readings[.headDown])
            XCTAssertEqual(reading.formattedRatio,expected)
        }
    }
    func testExactEntryBoundaryDoesNotStartTimer() throws {
        var judge=PostureJudge(baseline:base,smoothing:false)
        for t in 0...21 {
            let v=judge.update(pose(Issue.headDown.threshold),now:Double(t))
            let reading=try XCTUnwrap(v.readings[.headDown])
            XCTAssertEqual(reading.phase,.approaching)
            XCTAssertEqual(reading.elapsed,0)
            XCTAssertEqual(reading.ratio,1,accuracy:1e-9)
            XCTAssertTrue(v.alerts.isEmpty)
        }
    }
    func testEightyPercentIsApproachingAndOverThresholdUsesRealDwell() throws {
        var judge=PostureJudge(baseline:base,smoothing:false)
        XCTAssertEqual(judge.update(pose(0.159),now:0).readings[.headDown]?.phase,.below)
        XCTAssertEqual(judge.update(pose(0.16),now:1).readings[.headDown]?.phase,.approaching)
        _=judge.update(pose(0.21),now:2)
        for t in 3...21 {
            let reading=try XCTUnwrap(judge.update(pose(0.21),now:Double(t)).readings[.headDown])
            XCTAssertEqual(reading.phase,.counting)
            XCTAssertEqual(reading.elapsed,Double(t-2))
        }
        let verdict=judge.update(pose(0.21),now:22)
        XCTAssertEqual(verdict.readings[.headDown]?.phase,.active)
        XCTAssertEqual(verdict.alerts,[.headDown])
    }
    func testRecoveryUsesLowerBoundaryAndThreeSeconds() throws {
        var judge=PostureJudge(baseline:base,smoothing:false)
        for t in 0...20 {_=judge.update(pose(0.3),now:Double(t))}
        XCTAssertEqual(judge.update(pose(0.15),now:21).readings[.headDown]?.phase,.active)
        let reading=try XCTUnwrap(judge.update(pose(0.1),now:22).readings[.headDown])
        XCTAssertEqual(reading.recoveryThreshold,0.11,accuracy:1e-9)
        XCTAssertEqual(reading.phase,.recovering)
        XCTAssertEqual(judge.update(pose(0.1),now:24).readings[.headDown]?.elapsed,2)
        XCTAssertEqual(judge.update(pose(0.1),now:25).readings[.headDown]?.phase,.below)
    }
    func testMissingDisabledAndSnoozeDoNotClaimActiveCountdown() throws {
        var judge=PostureJudge(baseline:base,smoothing:false)
        _=judge.update(pose(0.3),now:0)
        XCTAssertTrue(judge.update(nil,now:1).readings.isEmpty)
        XCTAssertEqual(judge.update(pose(0.3),now:2).readings[.headDown]?.elapsed,0)
        XCTAssertEqual(judge.update(pose(0.3),now:3,muted:true).readings[.headDown]?.phase,.muted)
        judge.enabled.remove(.headDown)
        XCTAssertNil(judge.update(pose(0.3),now:4).readings[.headDown])
    }
    func testDisplayThresholdMatchesSensitivityAndUnits() throws {
        for sensitivity in [0.7,1.0,1.4] {
            var judge=PostureJudge(baseline:base,preferences:Preferences(sensitivity:sensitivity),smoothing:false)
            let reading=try XCTUnwrap(judge.update(pose(0.1),now:0).readings[.headDown])
            XCTAssertEqual(reading.threshold,0.2*sensitivity,accuracy:1e-9)
        }
        XCTAssertEqual(Issue.headDown.displayValue(0.2),11.4591559,accuracy:1e-6)
        XCTAssertEqual(Issue.shoulders.displayValue(0.14),8.021409,accuracy:1e-6)
        XCTAssertEqual(Issue.lean.displayValue(0.18),18,accuracy:1e-9)
    }
}
