import Foundation

/// Display only: raw geometry still feeds calibration/judgement. Never bridges missing frames.
public struct OverlayStabilizer {
    private var previous: [Point2] = []
    private var timestamp: Double?
    public init() {}
    public mutating func update(_ points: [Point2], now: Double) -> [Point2] {
        guard now.isFinite, points.allSatisfy({$0.x.isFinite && $0.y.isFinite}) else {
            previous=[];timestamp=nil;return []
        }
        let dt=timestamp.map {now-$0} ?? 0
        defer {timestamp=now}
        guard points.count == 3, previous.count == 3, dt > 0, dt <= 1 else {
            previous=points;return points
        }
        let width=hypot(points[0].x-points[1].x,points[0].y-points[1].y)
        let deadband=max(0.003,min(0.012,width*0.02))
        let alpha=1-exp(-dt/0.3)
        previous=zip(previous,points).map { old, new in
            let distance=hypot(new.x-old.x,new.y-old.y)
            guard distance > deadband else {return old}
            return Point2(x:old.x+alpha*(new.x-old.x),y:old.y+alpha*(new.y-old.y))
        }
        return previous
    }
}
