import Foundation

public struct SessionClock {
    public var interval: Double
    public private(set) var elapsed: Double = 0
    private var lastTick: Double?
    private var wasRunning = false
    private var notified = false
    public init(interval: Double = 2700) { self.interval = interval }
    public mutating func reset(now: Double) { elapsed = 0; lastTick = now; notified = false }
    public mutating func tick(now: Double, running: Bool, muted: Bool) -> Bool {
        defer { lastTick = now; wasRunning = running }
        guard running, wasRunning, let last = lastTick else { return false }
        let dt = now-last
        if dt > 0 && dt <= 5 { elapsed += dt }
        if elapsed >= interval && !notified {
            // Suppressed reminders are discarded rather than queued for later delivery.
            notified = true
            return !muted
        }
        return false
    }
}

/// Serializes camera-generation cancellation across capture, inference and UI queues.
public final class GenerationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    public init() {}
    public func advance() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    public var current: Int { lock.lock(); defer { lock.unlock() }; return value }
    public func accepts(_ candidate: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return value == candidate }
}

public struct FrameWatchdog {
    private var latest: Double?
    public init() {}
    public mutating func start(now: Double) { latest = now }
    public mutating func received(now: Double) { latest = now }
    public mutating func stop() { latest = nil }
    public func age(now: Double) -> Double { latest.map { max(0,now-$0) } ?? 0 }
    public func expired(now: Double) -> Bool { latest != nil && age(now: now) > 10 }
}

public struct ReminderAggregator {
    private var pending: [(channel: String?, text: String)] = []
    private var lastEnqueued: Double?
    private var lastSent: Double = -.infinity
    public init() {}
    public mutating func enqueue(_ text: String, channel: String? = nil, now: Double) {
        if let channel { pending.removeAll { $0.channel == channel } }
        if !pending.contains(where: { $0.text == text }) { pending.append((channel, text)) }
        lastEnqueued = now
    }
    public mutating func cancel(channel: String) {
        pending.removeAll { $0.channel == channel }
        if pending.isEmpty { lastEnqueued = nil }
    }
    public mutating func clearPending() { pending.removeAll(); lastEnqueued = nil }
    public mutating func take(now: Double) -> [String]? {
        guard !pending.isEmpty, let last = lastEnqueued, now-last >= 1, now-lastSent >= 60 else { return nil }
        let result = pending.map(\.text); pending.removeAll(); lastEnqueued = nil; lastSent = now
        return result
    }
}
