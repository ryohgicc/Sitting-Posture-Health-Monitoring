import Foundation

/// Only a clear majority of the locked face can reveal a person instance.
public enum PrivacySelection {
    /// Exactly one fresh detection may be preserved; all other faces are obscured.
    public static func targetFace(target: SubjectBox, faces: [SubjectBox]) -> Int? {
        let ranked=faces.indices.filter { faces[$0].valid }.sorted { faces[$0].overlap(target) > faces[$1].overlap(target) }
        guard target.valid, let first=ranked.first, faces[first].overlap(target) >= 0.6 else {return nil}
        if ranked.count > 1, faces[first].overlap(target)-faces[ranked[1]].overlap(target) < 0.2 {return nil}
        return first
    }
    public static func instance(coverage: [Int: Double]) -> Int? {
        let ranked = coverage.filter { $0.key > 0 && $0.value.isFinite && $0.value >= 0 && $0.value <= 1 }
            .sorted { $0.value > $1.value }
        guard let best = ranked.first, best.value >= 0.65 else { return nil }
        if ranked.count > 1, best.value-ranked[1].value < 0.25 { return nil }
        return best.key
    }
}
