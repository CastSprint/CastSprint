package com.castsprint.android.diag

/**
 * Thread-safe encoder/transport counters. FPS and bitrate are computed from frames actually
 * emitted by MediaCodec over a sliding 1 s window (encoder output rate, not end-to-end latency).
 */
class EncoderStats(private val clockNs: () -> Long = System::nanoTime) {
    data class Snapshot(
        val framesProduced: Long,
        val keyframes: Long,
        val framesDropped: Long,
        val framesUnsent: Long,
        val bytesProduced: Long,
        val encodedFps: Double,
        val encodedBitrateBps: Long,
        val thermalStatus: Int,
        val bitrateReduced: Boolean,
    )

    private val cap = 512
    private val times = LongArray(cap)
    private val sizes = IntArray(cap)
    private var head = 0
    private var count = 0
    private var produced = 0L
    private var keys = 0L
    private var dropped = 0L
    private var unsent = 0L
    private var bytes = 0L
    @Volatile var thermalStatus = 0
    @Volatile var bitrateReduced = false

    @Synchronized
    fun onFrame(size: Int, keyframe: Boolean) {
        produced++
        bytes += size
        if (keyframe) keys++
        val idx = (head + count) % cap
        times[idx] = clockNs()
        sizes[idx] = size
        if (count < cap) count++ else head = (head + 1) % cap
    }

    @Synchronized fun onDropped(n: Int) { dropped += n }
    @Synchronized fun onUnsent() { unsent++ }

    @Synchronized
    fun snapshot(): Snapshot {
        val now = clockNs()
        val windowNs = 1_000_000_000L
        // Expire samples older than the window.
        while (count > 0 && now - times[head] > windowNs) {
            head = (head + 1) % cap
            count--
        }
        var winBytes = 0L
        for (i in 0 until count) winBytes += sizes[(head + i) % cap]
        return Snapshot(
            produced, keys, dropped, unsent, bytes,
            encodedFps = count.toDouble(),
            encodedBitrateBps = winBytes * 8,
            thermalStatus = thermalStatus,
            bitrateReduced = bitrateReduced,
        )
    }
}
