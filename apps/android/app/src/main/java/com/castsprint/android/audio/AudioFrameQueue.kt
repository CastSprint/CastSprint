package com.castsprint.android.audio

import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

data class AudioPacket(
    val ptsUs: Long,
    val data: ByteArray,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is AudioPacket) return false
        return ptsUs == other.ptsUs && data.contentEquals(other.data)
    }

    override fun hashCode(): Int {
        var result = ptsUs.hashCode()
        result = 31 * result + data.contentHashCode()
        return result
    }
}

/**
 * Bounded queue for audio frames with real-time drop policy.
 * When the queue reaches capacity, the oldest audio packets are evicted to prevent
 * buffer buildup and keep audio in sync with low-latency video presentation.
 */
class AudioFrameQueue(private val capacity: Int = 16) {
    private val queue = ArrayBlockingQueue<AudioPacket>(capacity)
    private val droppedFramesCount = AtomicLong(0)

    fun offer(packet: AudioPacket): Boolean {
        while (queue.size >= capacity) {
            queue.poll() // Drop oldest packet to bound latency
            droppedFramesCount.incrementAndGet()
        }
        return queue.offer(packet)
    }

    fun poll(timeoutMs: Long): AudioPacket? {
        return queue.poll(timeoutMs, TimeUnit.MILLISECONDS)
    }

    fun clear() {
        queue.clear()
    }

    val size: Int get() = queue.size
    val droppedCount: Long get() = droppedFramesCount.get()
}
