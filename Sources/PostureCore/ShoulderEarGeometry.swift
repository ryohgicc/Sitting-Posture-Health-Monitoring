import Foundation

/// Pixel coordinates, y increasing downwards. Ear and shoulder labels must come from the same associated body.
public struct ShoulderEarGeometry {
    public let leftShoulder: Point2
    public let rightShoulder: Point2
    public let leftEar: Point2?
    public let rightEar: Point2?
    public let nose: Point2
    public init(leftShoulder: Point2, rightShoulder: Point2, leftEar: Point2?, rightEar: Point2?, nose: Point2) {
        self.leftShoulder=leftShoulder; self.rightShoulder=rightShoulder
        self.leftEar=leftEar; self.rightEar=rightEar; self.nose=nose
    }
    public var gaps: (left:Double,right:Double)? {
        guard let leftEar, let rightEar,
              [leftShoulder,rightShoulder,leftEar,rightEar,nose].allSatisfy({$0.x.isFinite && $0.y.isFinite}) else {return nil}
        // Use horizontal span: a unilateral lift lengthens the diagonal and would
        // otherwise shrink the stationary side's normalized gap as well.
        let width=abs(rightShoulder.x-leftShoulder.x)
        let diagonal=hypot(rightShoulder.x-leftShoulder.x,rightShoulder.y-leftShoulder.y)
        let earWidth=abs(rightEar.x-leftEar.x)
        guard width > 30, width/diagonal > 0.85,
              (rightEar.x-leftEar.x)*(rightShoulder.x-leftShoulder.x) > 0,
              earWidth/width > 0.12, earWidth/width < 0.8,
              abs(leftEar.y-rightEar.y)/earWidth < 0.22,
              abs((leftEar.x+rightEar.x)/2-nose.x)/width < 0.15,
              abs((leftEar.y+rightEar.y)/2-nose.y)/width < 0.3 else {return nil}
        let left=(leftShoulder.y-leftEar.y)/width
        let right=(rightShoulder.y-rightEar.y)/width
        guard left > 0.03, right > 0.03, left < 2, right < 2 else {return nil}
        return (left,right)
    }
}
