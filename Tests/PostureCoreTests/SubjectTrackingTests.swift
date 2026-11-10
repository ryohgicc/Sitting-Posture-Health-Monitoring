import XCTest
@testable import PostureCore

final class SubjectTrackingTests: XCTestCase {
    private let front = SubjectBox(x: 0.35, y: 0.35, width: 0.24, height: 0.38)
    private let background = SubjectBox(x: 0.08, y: 0.5, width: 0.06, height: 0.1)

    func testLargeForegroundIsSelectedDespiteManyBackgroundFaces() {
        var tracker = SubjectTracker()
        let result = tracker.select([background,front,SubjectBox(x: 0.8,y: 0.4,width: 0.08,height: 0.12)], now: 0)
        XCTAssertEqual(result.index, 1)
        XCTAssertEqual(result.status, .locked)
    }
    func testArrayOrderAndLargerBystanderDoNotSwitchLockedSubject() {
        var tracker = SubjectTracker()
        _ = tracker.select([front], now: 0)
        let bystander = SubjectBox(x: 0.7,y: 0.3,width: 0.29,height: 0.4)
        XCTAssertEqual(tracker.select([bystander,front],now: 0.2).index, 1)
    }
    func testMissingTargetDoesNotSelectBackgroundOrNewPerson() {
        var tracker = SubjectTracker()
        _ = tracker.select([front,background], now: 0)
        XCTAssertNil(tracker.select([background], now: 0.2).index)
        XCTAssertEqual(tracker.select([background], now: 3).status, .needsReset)
        XCTAssertNil(tracker.select([front],now: 3.2).index)
        tracker.reset()
        XCTAssertEqual(tracker.select([front],now: 3.4).index, 0)
    }
    func testSimilarForegroundCandidatesAreAmbiguous() {
        var tracker = SubjectTracker()
        let left = SubjectBox(x:0.18,y:0.35,width:0.24,height:0.38)
        let right = SubjectBox(x:0.58,y:0.35,width:0.24,height:0.38)
        XCTAssertNil(tracker.select([left,right],now:0).index)
    }
    func testOccludingFacesDoNotChangeTarget() {
        var tracker = SubjectTracker()
        _ = tracker.select([front],now:0)
        let overlapping = SubjectBox(x:0.4,y:0.35,width:0.24,height:0.38)
        XCTAssertNil(tracker.select([front,overlapping],now:0.2).index)
    }
    func testSmallBackgroundFacesCannotInitiallyAcquire() {
        var tracker = SubjectTracker()
        XCTAssertNil(tracker.select([background],now:0).index)
    }
    func testTrackingGapRequiresExplicitReset() {
        var tracker = SubjectTracker()
        _ = tracker.select([front],now:0)
        XCTAssertEqual(tracker.select([front],now:5).status, .needsReset)
    }
    func testResetAllowsNewTargetAndInvalidBoxesAreIgnored() {
        var tracker = SubjectTracker()
        XCTAssertNil(tracker.select([SubjectBox(x:.nan,y:0,width:1,height:1)],now:0).index)
        _ = tracker.select([front],now:0.2)
        tracker.reset()
        let other = SubjectBox(x:0.5,y:0.2,width:0.3,height:0.4)
        XCTAssertEqual(tracker.select([other],now:0.4).index,0)
    }
    func testBodyAssociationRejectsBackgroundBodyAndNeedsUniqueMatch() {
        let wrong = BodyAnchor(nose: Point2(x:0.1,y:0.55), leftShoulder: Point2(x:0,y:0.4), rightShoulder: Point2(x:0.2,y:0.4))
        let correct = BodyAnchor(nose: Point2(x:0.47,y:0.5), leftShoulder: Point2(x:0.3,y:0.32), rightShoulder: Point2(x:0.65,y:0.32))
        XCTAssertEqual(SubjectAssociation.bodyIndex(for:front,candidates:[wrong,correct]),1)
        XCTAssertNil(SubjectAssociation.bodyIndex(for:front,candidates:[correct,correct]))
        XCTAssertNil(SubjectAssociation.bodyIndex(for:front,candidates:[wrong]))
    }
    func testMissingBodyNoseDoesNotBorrowBystanderShoulders() {
        let unanchored = BodyAnchor(nose:nil,leftShoulder:Point2(x:0.3,y:0.3),rightShoulder:Point2(x:0.65,y:0.3))
        XCTAssertNil(SubjectAssociation.bodyIndex(for:front,candidates:[unanchored]))
    }
    func testPreviewMappingAccountsForLetterboxAndMirror() {
        let mapped = PreviewGeometry.map(Point2(x:0,y:1), sourceAspect:16.0/9, width:400, height:300)
        XCTAssertEqual(mapped.x,400,accuracy:0.001)
        XCTAssertEqual(mapped.y,37.5,accuracy:0.001)
        let center = PreviewGeometry.map(Point2(x:0.5,y:0.5),sourceAspect:16.0/9,width:400,height:300)
        XCTAssertEqual(center.x,200,accuracy:0.001)
        XCTAssertEqual(center.y,150,accuracy:0.001)
    }
}

extension SubjectTrackingTests {
    func testExplicitPickResolvesSimilarFacesButNotOverlappingFaces() {
        var tracker=SubjectTracker()
        let a=SubjectBox(x:0.18,y:0.3,width:0.24,height:0.38)
        let b=SubjectBox(x:0.58,y:0.3,width:0.24,height:0.38)
        tracker.reset(pick:Point2(x:0.7,y:0.5))
        XCTAssertEqual(tracker.select([a,b],now:0).index,1)
        tracker.reset(pick:Point2(x:0.7,y:0.5))
        XCTAssertNil(tracker.select([b,b],now:0.2).index)
    }
    func testClickingLetterboxDoesNotSelectAnyone() {
        XCTAssertNil(PreviewGeometry.unmap(Point2(x:200,y:10),sourceAspect:16.0/9,width:400,height:300))
        let selected=PreviewGeometry.unmap(Point2(x:300,y:150),sourceAspect:16.0/9,width:400,height:300)
        XCTAssertEqual(selected!.x,0.25,accuracy:0.001)
        XCTAssertEqual(selected!.y,0.5,accuracy:0.001)
    }
}
