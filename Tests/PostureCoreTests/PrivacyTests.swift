import XCTest
@testable import PostureCore

final class PrivacyTests: XCTestCase {
    func testOverlappingBystanderIsNotTreatedAsTarget() {
        let target=SubjectBox(x:0.3,y:0.4,width:0.3,height:0.3)
        let bystander=SubjectBox(x:0.4,y:0.4,width:0.2,height:0.2)
        XCTAssertEqual(PrivacySelection.targetFace(target:target,faces:[bystander,target]),1)
        XCTAssertNil(PrivacySelection.targetFace(target:target,faces:[target,target]))
        XCTAssertNil(PrivacySelection.targetFace(target:target,faces:[]))
    }
    func testOnlyTargetCoveringInstanceSelected() {
        XCTAssertEqual(PrivacySelection.instance(coverage: [1:0.1, 2:0.95, 3:0.3]), 2)
    }
    func testAmbiguousAndWeakMasksNeverRevealPeople() {
        XCTAssertNil(PrivacySelection.instance(coverage: [1:0.75, 2:0.7]))
        XCTAssertNil(PrivacySelection.instance(coverage: [1:0.4]))
        XCTAssertNil(PrivacySelection.instance(coverage: [:]))
        XCTAssertNil(PrivacySelection.instance(coverage: [0:1, 1:Double.nan]))
    }
}
