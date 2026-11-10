import XCTest
@testable import PostureCore

final class HeadApproachTests: XCTestCase {
    private func metrics(ratio:Double=0.4,span:Double=0.5,pitch:Double=0,roll:Double=0,yaw:Double=0,lateral:Double=0) -> PoseMetrics {
        PoseMetrics(headPitch:pitch,lateral:lateral,shoulderTilt:0,headRoll:roll,headScale:ratio,shoulderSpan:span,headYaw:yaw)
    }
    func testFrontalHeadShoulderRatioUsesSameFrameAndRejectsBadAnchors() throws {
        let geometry=HeadApproachGeometry(face:SubjectBox(x:0.4,y:0.5,width:0.2,height:0.3),leftShoulder:Point2(x:0.25,y:0.35),rightShoulder:Point2(x:0.75,y:0.35),nose:Point2(x:0.5,y:0.65),imageWidth:1000,imageHeight:600)
        XCTAssertEqual(try XCTUnwrap(geometry.scaleRatio),0.4,accuracy:0.0001)
        let bigger=HeadApproachGeometry(face:SubjectBox(x:0.35,y:0.45,width:0.3,height:0.45),leftShoulder:Point2(x:0.125,y:0.225),rightShoulder:Point2(x:0.875,y:0.225),nose:Point2(x:0.5,y:0.675),imageWidth:1000,imageHeight:600)
        XCTAssertEqual(try XCTUnwrap(bigger.scaleRatio),0.4,accuracy:0.0001)
        XCTAssertNil(HeadApproachGeometry(face:SubjectBox(x:0.4,y:0.5,width:0.2,height:0.3),leftShoulder:Point2(x:0.49,y:0.35),rightShoulder:Point2(x:0.51,y:0.35),nose:Point2(x:0.5,y:0.65),imageWidth:1000,imageHeight:600).scaleRatio)
        XCTAssertNil(HeadApproachGeometry(face:SubjectBox(x:0.4,y:0.5,width:0.2,height:0.3),leftShoulder:Point2(x:0.25,y:0.35),rightShoulder:Point2(x:0.75,y:0.35),nose:Point2(x:0.9,y:0.65),imageWidth:1000,imageHeight:600).scaleRatio)
    }
    func testOnlyRelativeIncreaseCountsAndBodyOrHeadMotionIsUnknown() throws {
        let base=metrics()
        XCTAssertEqual(try XCTUnwrap(metrics(ratio:0.46).signedDeviation(from:base,issue:.headForward)),0.15,accuracy:0.0001)
        XCTAssertEqual(try XCTUnwrap(metrics(ratio:0.36).signedDeviation(from:base,issue:.headForward)),-0.1,accuracy:0.0001)
        XCTAssertNil(metrics(ratio:0.46,span:0.6).signedDeviation(from:base,issue:.headForward))
        XCTAssertNil(metrics(ratio:0.46,pitch:0.11).signedDeviation(from:base,issue:.headForward))
        XCTAssertNil(metrics(ratio:0.46,roll:0.11).signedDeviation(from:base,issue:.headForward))
        XCTAssertNil(metrics(ratio:0.46,yaw:0.11).signedDeviation(from:base,issue:.headForward))
        XCTAssertNil(metrics(ratio:0.46,lateral:0.11).signedDeviation(from:base,issue:.headForward))
    }
    func testDwellAndMissingForwardMetricResetIndependently() {
        let base=metrics(),forward=metrics(ratio:0.46)
        var judge=PostureJudge(baseline:base,smoothing:false)
        for t in 0...4 {XCTAssertFalse(judge.update(forward,now:Double(t)).active.contains(.headForward))}
        XCTAssertEqual(judge.update(forward,now:5).alerts,[.headForward])
        let down=metrics(ratio:0.46,pitch:0.3)
        for t in 6...11 {XCTAssertNil(judge.update(down,now:Double(t)).readings[.headForward])}
        XCTAssertTrue(judge.update(down,now:12).active.contains(.headDown))
        XCTAssertFalse(judge.update(forward,now:13).active.contains(.headForward))
        var backwards=PostureJudge(baseline:base,smoothing:false)
        for t in 0...8 {XCTAssertFalse(backwards.update(metrics(ratio:0.3),now:Double(t)).active.contains(.headForward))}
    }
    func testStableCalibrationAndLegacyJSON() throws {
        var accumulator=CalibrationAccumulator()
        for n in 0...50 {accumulator.add(metrics(),now:Double(n)*0.2)}
        let base=try XCTUnwrap(accumulator.result(now:10))
        XCTAssertEqual(base.headScale,0.4);XCTAssertEqual(base.shoulderSpan,0.5);XCTAssertEqual(base.headYaw,0)
        let data=Data(#"{"headPitch":0,"lateral":0,"shoulderTilt":0}"#.utf8)
        let old=try JSONDecoder().decode(PoseMetrics.self,from:data)
        XCTAssertNil(old[.headForward])
        XCTAssertNil(metrics(ratio:0.5).signedDeviation(from:old,issue:.headForward))
        let profile=PersonalProfile(baseline:base,thresholds:[.headForward:0.15])
        XCTAssertNotNil(try JSONDecoder().decode(PersonalProfile.self,from:JSONEncoder().encode(profile)).validated)
        XCTAssertFalse(profile.matches(metrics(span:0.51)))
    }
    func testReferenceRejectsRelativeScaleNoiseAndChangingShoulderScale() throws {
        var noisy=CalibrationAccumulator(), moving=CalibrationAccumulator()
        for n in 0...50 {
            let t=Double(n)*0.2
            noisy.add(metrics(ratio:n%2 == 0 ? 0.2 : 0.23),now:t)
            moving.add(metrics(ratio:0.2,span:n%2 == 0 ? 0.1 : 0.12),now:t)
        }
        XCTAssertNil(try XCTUnwrap(noisy.result(now:10)).headScale)
        XCTAssertNil(try XCTUnwrap(moving.result(now:10)).headScale)
        XCTAssertEqual(noisy.result(now:10)?.headPitch,0)
    }
    func testGuideLearnsHeadApproachAndRejectsBodyApproach() throws {
        var session=AdaptationSession(preferences:Preferences())
        for n in 0...60 {session.update(metrics(),now:Double(n)*0.2)}
        for _ in 0..<4 {session.skip()}
        XCTAssertEqual(session.step,.headForward)
        for n in 0...15 {session.update(metrics(ratio:0.46,span:0.6),now:13+Double(n)*0.2)}
        XCTAssertFalse(session.record())
        for n in 0...20 {session.update(metrics(ratio:0.46),now:17+Double(n)*0.2)}
        XCTAssertTrue(session.record())
        XCTAssertEqual(session.step,.experience)
        XCTAssertEqual(try XCTUnwrap(session.profile?.thresholds[.headForward]),0.15,accuracy:0.0001)
    }
}
