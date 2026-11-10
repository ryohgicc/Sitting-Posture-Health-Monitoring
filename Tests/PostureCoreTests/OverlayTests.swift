import XCTest
@testable import PostureCore

final class OverlayTests: XCTestCase {
    private let base=[Point2(x:0.3,y:0.3),Point2(x:0.7,y:0.3),Point2(x:0.5,y:0.7)]
    func testSmallStationaryNoiseDoesNotMoveOverlay() {
        var filter=OverlayStabilizer()
        _=filter.update(base,now:0)
        for i in 1...20 {
            let offset=i%2 == 0 ? 0.006 : -0.006
            let noisy=base.map {Point2(x:$0.x,y:$0.y+offset)}
            let result=filter.update(noisy,now:Double(i)*0.2)
            XCTAssertEqual(result[0].y,base[0].y,accuracy:0.0001)
            XCTAssertEqual(result[1].y,base[1].y,accuracy:0.0001)
        }
    }
    func testRealMovementFollowsWithoutLongFreeze() {
        var filter=OverlayStabilizer()
        _=filter.update(base,now:0)
        let moved=base.map {Point2(x:$0.x,y:$0.y+0.12)}
        var result=base
        for i in 1...4 { result=filter.update(moved,now:Double(i)*0.2) }
        XCTAssertGreaterThan(result[0].y,0.4)
        XCTAssertLessThanOrEqual(result[0].y,0.42)
    }
    func testMissingOrLongGapNeverReusesOldSkeleton() {
        var filter=OverlayStabilizer()
        _=filter.update(base,now:0)
        XCTAssertTrue(filter.update([],now:0.2).isEmpty)
        let moved=base.map {Point2(x:$0.x+0.1,y:$0.y)}
        XCTAssertEqual(filter.update(moved,now:0.4)[0].x,0.4,accuracy:0.0001)
        XCTAssertEqual(filter.update(base,now:3)[0].x,0.3,accuracy:0.0001)
        XCTAssertEqual(filter.update([base[2]],now:3.2).count,1)
        XCTAssertEqual(filter.update(moved,now:3.4)[0].x,0.4,accuracy:0.0001)
    }
}
