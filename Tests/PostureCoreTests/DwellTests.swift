import XCTest
@testable import PostureCore

final class DwellTests: XCTestCase {
    func testDefaultAlertsAtFiveSecondsAndCustomDurationAtSeven() {
        let baseline=PoseMetrics(headPitch:0,lateral:0,shoulderTilt:0)
        let down=PoseMetrics(headPitch:0.3,lateral:0,shoulderTilt:0)
        for duration in [5.0,7] {
            var judge=PostureJudge(baseline:baseline,preferences: duration == 5 ? Preferences() : Preferences(dwell:duration),smoothing:false)
            for t in 0..<Int(duration) {XCTAssertTrue(judge.update(down,now:Double(t)).alerts.isEmpty)}
            XCTAssertEqual(judge.update(down,now:duration).alerts,[.headDown])
        }
    }
    func testCustomDurationPersistsAndInvalidValuesAreBounded() throws {
        for seconds in [1.0,5,7,20,120] {
            let data=try JSONEncoder().encode(Preferences(dwell:seconds))
            XCTAssertEqual(try JSONDecoder().decode(Preferences.self,from:data).validated.dwell,seconds)
        }
        XCTAssertEqual(Preferences(dwell:.nan).dwell,5)
        XCTAssertEqual(Preferences(dwell:-1).dwell,1)
        XCTAssertEqual(Preferences(dwell:121).dwell,120)
        XCTAssertEqual(Preferences(dwell:5.8).dwell,6)
    }
}
