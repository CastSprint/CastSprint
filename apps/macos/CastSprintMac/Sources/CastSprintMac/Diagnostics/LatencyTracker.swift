// LatencyTracker.swift — Real-Time FPS, Latency, and Jitter Tracker
import Foundation
import QuartzCore

public final class LatencyTracker {
    public static let shared = LatencyTracker()

    private var frameCount: UInt64 = 0
    private var lastFpsUpdateTime: CFTimeInterval = CACurrentMediaTime()
    private var lastFrameTime: CFTimeInterval = 0

    public private(set) var currentFps: Double = 0.0
    public private(set) var averageFrameTimeMs: Double = 0.0
    public private(set) var jitterMs: Double = 0.0
    public private(set) var droppedFrames: UInt64 = 0

    private init() {}

    public func recordFrameReceived() {
        let now = CACurrentMediaTime()
        frameCount += 1

        if lastFrameTime > 0 {
            let deltaMs = (now - lastFrameTime) * 1000.0
            let diff = abs(deltaMs - 16.666) // 60 FPS target interval
            jitterMs = (jitterMs * 0.9) + (diff * 0.1)
            averageFrameTimeMs = (averageFrameTimeMs * 0.9) + (deltaMs * 0.1)
        }
        lastFrameTime = now

        let elapsed = now - lastFpsUpdateTime
        if elapsed >= 1.0 {
            currentFps = Double(frameCount) / elapsed
            frameCount = 0
            lastFpsUpdateTime = now
        }
    }

    public func recordDroppedFrame() {
        droppedFrames += 1
    }

    public func reset() {
        frameCount = 0
        lastFpsUpdateTime = CACurrentMediaTime()
        lastFrameTime = 0
        currentFps = 0.0
        averageFrameTimeMs = 0.0
        jitterMs = 0.0
        droppedFrames = 0
    }
}
