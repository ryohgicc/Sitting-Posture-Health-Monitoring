import Foundation

/// Geometry only; no face identity, images or recognition embeddings are retained.
public struct SubjectBox: Equatable, Sendable {
    public let x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var area: Double { width * height }
    public var center: Point2 { Point2(x: x + width/2, y: y + height/2) }
    public var valid: Bool {
        [x,y,width,height].allSatisfy(\.isFinite) && width > 0 && height > 0 && x >= 0 && y >= 0 && x+width <= 1.001 && y+height <= 1.001
    }
    public func contains(_ point: Point2) -> Bool { point.x >= x && point.x <= x+width && point.y >= y && point.y <= y+height }
    public func overlap(_ other: SubjectBox) -> Double {
        let intersection = max(0,min(x+width,other.x+other.width)-max(x,other.x)) * max(0,min(y+height,other.y+other.height)-max(y,other.y))
        return intersection / max(0.000001,area+other.area-intersection)
    }
}

public enum SubjectStatus: String, Sendable { case searching, locked, ambiguous, missing, needsReset }
public struct SubjectSelection: Sendable {
    public let index: Int?
    public let status: SubjectStatus
    public let newLock: Bool
}

public struct SubjectTracker {
    private var anchor: SubjectBox?
    private var seenAt: Double?
    private var requiresReset = false
    private var pick: Point2?
    public init() {}
    public mutating func reset(pick: Point2? = nil) { anchor = nil; seenAt = nil; requiresReset = false; self.pick = pick }
    public mutating func select(_ boxes: [SubjectBox], now: Double) -> SubjectSelection {
        func result(_ index: Int? = nil, _ status: SubjectStatus, _ newLock: Bool = false) -> SubjectSelection { SubjectSelection(index: index,status: status,newLock: newLock) }
        guard now.isFinite else { return result(nil,.missing) }
        if let last = seenAt, now-last > 2 || now < last { requiresReset = true }
        if requiresReset { return result(nil,.needsReset) }
        let eligible = boxes.indices.filter { boxes[$0].valid && boxes[$0].width >= 0.09 && boxes[$0].area >= 0.012 }
        if let anchor {
            let matched = eligible.filter { i in
                let b = boxes[i], distance = hypot(b.center.x-anchor.center.x,b.center.y-anchor.center.y)
                return b.area/anchor.area > 0.5 && b.area/anchor.area < 2 && distance < max(0.06,anchor.width*0.55) && b.overlap(anchor) > 0.25
            }
            guard matched.count == 1, let i = matched.first else { return result(nil, matched.isEmpty ? .missing : .ambiguous) }
            self.anchor = boxes[i]; seenAt = now
            return result(i,.locked)
        }
        if let pick {
            let hits = eligible.filter { boxes[$0].contains(pick) }
            guard hits.count == 1, let i = hits.first else { return result(nil,.ambiguous) }
            self.pick = nil; self.anchor = boxes[i]; seenAt = now
            return result(i,.locked,true)
        }
        // Largest central face normally belongs to the laptop user. Do not guess among similar-size faces.
        let central = eligible.filter { boxes[$0].center.x > 0.2 && boxes[$0].center.x < 0.8 }
        let ranked = central.sorted { boxes[$0].area > boxes[$1].area }
        guard let i = ranked.first else { return result(nil,.searching) }
        let rivals = eligible.filter { $0 != i && boxes[$0].area > boxes[i].area*0.6 }
        guard rivals.isEmpty else { return result(nil,.ambiguous) }
        anchor = boxes[i]; seenAt = now
        return result(i,.locked,true)
    }
}

public struct BodyAnchor: Sendable {
    public let nose: Point2?
    public let leftShoulder: Point2?
    public let rightShoulder: Point2?
    public let leftEar: Point2?
    public let rightEar: Point2?
    public init(nose: Point2?, leftShoulder: Point2?, rightShoulder: Point2?, leftEar: Point2? = nil, rightEar: Point2? = nil) {
        self.nose = nose; self.leftShoulder = leftShoulder; self.rightShoulder = rightShoulder
        self.leftEar = leftEar; self.rightEar = rightEar
    }
}
public enum SubjectAssociation {
    public static func bodyIndex(for face: SubjectBox, candidates: [BodyAnchor]) -> Int? {
        let matches = candidates.indices.filter { i in
            guard let nose = candidates[i].nose, face.contains(nose), let l = candidates[i].leftShoulder, let r = candidates[i].rightShoulder else { return false }
            let shoulderY = (l.y+r.y)/2
            return [nose.x,nose.y,l.x,l.y,r.x,r.y].allSatisfy(\.isFinite) && abs((l.x+r.x)/2-face.center.x) < face.width*0.85 && shoulderY < face.center.y && abs(l.x-r.x) > face.width*0.8
        }
        return matches.count == 1 ? matches.first : nil
    }
}

public enum PreviewGeometry {
    public static func map(_ point: Point2, sourceAspect: Double, width: Double, height: Double) -> Point2 {
        let contentWidth = min(width,height*sourceAspect)
        let contentHeight = contentWidth/sourceAspect
        return Point2(x: (width-contentWidth)/2+(1-point.x)*contentWidth,y:(height-contentHeight)/2+(1-point.y)*contentHeight)
    }
    public static func unmap(_ point: Point2, sourceAspect: Double, width: Double, height: Double) -> Point2? {
        let contentWidth = min(width,height*sourceAspect), contentHeight = contentWidth/sourceAspect
        let p = Point2(x:1-(point.x-(width-contentWidth)/2)/contentWidth,y:1-(point.y-(height-contentHeight)/2)/contentHeight)
        return p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1 ? p : nil
    }
}
