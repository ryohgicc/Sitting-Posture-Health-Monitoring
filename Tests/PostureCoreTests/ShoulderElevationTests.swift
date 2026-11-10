import XCTest
@testable import PostureCore

final class ShoulderElevationTests: XCTestCase {
    private func geometry(raisedLeft:Double=0,raisedRight:Double=0,scale:Double=1,shift:Double=0) -> ShoulderEarGeometry {
        func p(_ x:Double,_ y:Double)->Point2 {Point2(x:x*scale+shift,y:y*scale+shift)}
        return ShoulderEarGeometry(leftShoulder:p(100,300-raisedLeft),rightShoulder:p(300,300-raisedRight),leftEar:p(160,100),rightEar:p(240,100),nose:p(200,130))
    }
    private func metrics(_ left:Double?,_ right:Double?,pitch:Double=0,roll:Double=0)->PoseMetrics {
        PoseMetrics(headPitch:pitch,lateral:0,shoulderTilt:0,leftEarGap:left,rightEarGap:right,headRoll:roll)
    }
    func testBilateralReductionIsScaleAndTranslationInvariantAndSingleShoulderDoesNotCount() throws {
        let b=geometry(), up=geometry(raisedLeft:20,raisedRight:20)
        XCTAssertEqual(try XCTUnwrap(b.gaps).left,1,accuracy:0.0001)
        XCTAssertEqual(try XCTUnwrap(up.gaps).left,0.9,accuracy:0.0001)
        let shifted=geometry(raisedLeft:20,raisedRight:20,scale:2,shift:50)
        XCTAssertEqual(try XCTUnwrap(shifted.gaps).left,0.9,accuracy:0.0001)
        let base=metrics(1,1)
        XCTAssertEqual(try XCTUnwrap(metrics(0.9,0.9).signedDeviation(from:base,issue:.shrug)),0.1,accuracy:0.0001)
        XCTAssertEqual(try XCTUnwrap(metrics(0.8,1).signedDeviation(from:base,issue:.shrug)),0,accuracy:0.0001)
        XCTAssertLessThan(try XCTUnwrap(metrics(1.1,1.1).signedDeviation(from:base,issue:.shrug)),0)
    }
    func testLargeSingleSideLiftThroughGeometryDoesNotCreateBilateralEvent() throws {
        let before=try XCTUnwrap(geometry().gaps)
        let after=try XCTUnwrap(geometry(raisedLeft:100).gaps)
        let baseline=metrics(before.left,before.right)
        let single=metrics(after.left,after.right)
        XCTAssertEqual(try XCTUnwrap(single.signedDeviation(from:baseline,issue:.shrug)),0,accuracy:0.0001)
        var judge=PostureJudge(baseline:baseline,smoothing:false)
        for t in 0...8 {XCTAssertFalse(judge.update(single,now:Double(t)).active.contains(.shrug))}
    }
    func testMissingEarsImplausibleGeometryAndHeadMotionRemainUnknown() {
        XCTAssertNil(ShoulderEarGeometry(leftShoulder:Point2(x:100,y:300),rightShoulder:Point2(x:300,y:300),leftEar:nil,rightEar:Point2(x:240,y:100),nose:Point2(x:200,y:130)).gaps)
        XCTAssertNil(ShoulderEarGeometry(leftShoulder:Point2(x:100,y:300),rightShoulder:Point2(x:300,y:300),leftEar:Point2(x:50,y:400),rightEar:Point2(x:450,y:400),nose:Point2(x:200,y:130)).gaps)
        let base=metrics(1,1)
        XCTAssertNil(metrics(nil,0.8).signedDeviation(from:base,issue:.shrug))
        XCTAssertNil(metrics(0.8,0.8,pitch:0.2).signedDeviation(from:base,issue:.shrug))
        XCTAssertNil(metrics(0.8,0.8,roll:0.2).signedDeviation(from:base,issue:.shrug))
        XCTAssertNil(metrics(0.8,0.8).signedDeviation(from:PoseMetrics(headPitch:0,lateral:0,shoulderTilt:0),issue:.shrug))
    }
    func testBilateralDwellMissingResetAndCalibration() throws {
        let base=metrics(1,1),up=metrics(0.9,0.9)
        var calibration=CalibrationAccumulator()
        for n in 0...50 {calibration.add(base,now:Double(n)*0.2)}
        XCTAssertEqual(try XCTUnwrap(calibration.result(now:10)).leftEarGap,1)
        var judge=PostureJudge(baseline:base,smoothing:false)
        for t in 0...4 {XCTAssertFalse(judge.update(up,now:Double(t)).active.contains(.shrug))}
        XCTAssertEqual(judge.update(up,now:5).alerts,[.shrug])
        XCTAssertNil(judge.update(metrics(nil,0.9),now:6).readings[.shrug])
        XCTAssertFalse(judge.update(up,now:7).active.contains(.shrug))
        var single=PostureJudge(baseline:base,smoothing:false)
        for t in 0...8 {XCTAssertFalse(single.update(metrics(0.7,1),now:Double(t)).active.contains(.shrug))}
    }
    func testLegacyReferenceAndProfileDecodeWithoutCreatingShrugBaseline() throws {
        let data=Data(#"{"headPitch":0,"lateral":0,"shoulderTilt":0}"#.utf8)
        let baseline=try JSONDecoder().decode(PoseMetrics.self,from:data)
        XCTAssertNil(baseline[.shrug])
        let p=PersonalProfile(baseline:baseline,thresholds:[.shoulders:0.12])
        XCTAssertNotNil(try JSONDecoder().decode(PersonalProfile.self,from:JSONEncoder().encode(p)).validated)
        var judge=PostureJudge(baseline:baseline,smoothing:false)
        XCTAssertNil(judge.update(metrics(0.8,0.8),now:0).readings[.shrug])
    }
    func testGuidedShrugRecordsBilateralChangeAndRejectsOneSide() throws {
        var session=AdaptationSession(preferences:Preferences())
        for n in 0...60 {session.update(metrics(1,1),now:Double(n)*0.2)}
        for _ in 0..<3 {session.skip()}
        XCTAssertEqual(session.step,.shrug)
        for n in 0...15 {session.update(metrics(0.8,1),now:13+Double(n)*0.2)}
        XCTAssertFalse(session.record())
        for n in 0...20 {session.update(metrics(0.9,0.9),now:17+Double(n)*0.2)}
        XCTAssertTrue(session.record())
        session.skip() // New optional head approach step.
        XCTAssertEqual(session.step,.experience)
        XCTAssertEqual(try XCTUnwrap(session.profile?.thresholds[.shrug]),0.1,accuracy:0.0001)
    }
}
