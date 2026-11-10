import Foundation

/// Frontal-camera proxy, not a neck angle. All normalized anchors must belong to the same face/body.
public struct HeadApproachGeometry {
    public let face: SubjectBox
    public let leftShoulder: Point2
    public let rightShoulder: Point2
    public let nose: Point2
    public let imageWidth: Double
    public let imageHeight: Double
    public init(face: SubjectBox, leftShoulder: Point2, rightShoulder: Point2, nose: Point2, imageWidth: Double, imageHeight: Double) {
        self.face=face; self.leftShoulder=leftShoulder; self.rightShoulder=rightShoulder
        self.nose=nose; self.imageWidth=imageWidth; self.imageHeight=imageHeight
    }
    public var shoulderSpan: Double { abs(rightShoulder.x-leftShoulder.x) }
    public var scaleRatio: Double? {
        guard face.valid, face.contains(nose), imageWidth.isFinite, imageHeight.isFinite,
              imageWidth > 0, imageHeight > 0,
              [leftShoulder,rightShoulder,nose].allSatisfy({$0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)}) else {return nil}
        let horizontal=shoulderSpan*imageWidth
        let diagonal=hypot(horizontal,(rightShoulder.y-leftShoulder.y)*imageHeight)
        guard horizontal > 30, horizontal/diagonal > 0.94,
              (leftShoulder.y+rightShoulder.y)/2 < face.center.y,
              abs((leftShoulder.x+rightShoulder.x)/2-face.center.x) < face.width*0.7 else {return nil}
        let ratio=face.width/shoulderSpan
        return ratio > 0.12 && ratio < 0.9 ? ratio : nil
    }
}
