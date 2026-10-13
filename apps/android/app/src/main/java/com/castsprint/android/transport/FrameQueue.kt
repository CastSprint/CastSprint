package com.castsprint.android.transport

import com.castsprint.android.protocol.ProtocolV1
import java.util.ArrayDeque
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** One encoded access unit in a pooled buffer. Ownership moves encoder -> queue -> sink -> pool. */
class EncodedFrame(var data: ByteArray) {
    var length = 0
    var ptsUs = 0L
    var flags = 0
    var configId = 0
    val isKeyframe get() = flags and ProtocolV1.FRAME_KEYFRAME != 0
}

/** Bounded pool of frame buffers to avoid per-frame allocation at 60 fps. */
class FramePool(private val maxPooled: Int = 16) {
    private val free = ArrayDeque<EncodedFrame>()

    @Synchronized
    fun acquire(minCapacity: Int): EncodedFrame {
        val it = free.iterator()
        while (it.hasNext()) {
            val f = it.next()
            if (f.data.size >= minCapacity) {
                it.remove()
                return f.also { f.length = 0; f.flags = 0 }
            }
        }
        // Grow in 64 KiB steps so buffers are reusable across slightly larger frames.
        return EncodedFrame(ByteArray(((minCapacity + 0xFFFF) / 0x10000) * 0x10000))
    }

    @Synchronized
    fun release(f: EncodedFrame) {
        if (free.size >= maxPooled) free.pollFirst() // drop the oldest buffer
        free.addLast(f)
    }

    @Synchronized
    fun pooledCount() = free.size
}

data class VideoConfigInfo(
    val configId: Int,
    val profile: Int,
    val level: Int,
    val width: Int,
    val height: Int,
    val fps: Int,
    val bitrate: Int,
    val csd: ByteArray,
) {
    override fun equals(other: Any?) = other is VideoConfigInfo && configId == other.configId &&
        width == other.width && height == other.height && csd.contentEquals(other.csd)
    override fun hashCode() = 31 * configId + csd.contentHashCode()
}

sealed class Outbound {
    data class Config(val info: VideoConfigInfo) : Outbound()
    class Frame(val frame: EncodedFrame) : Outbound()
    data class DisplayChanged(val width: Int, val height: Int, val nextConfigId: Int) : Outbound()
    data class Disconnect(val reason: Int, val message: String) : Outbound()
}

data class OfferResult(val dropped: Int, val keyframeNeeded: Boolean)

/**
 * Bounded queue between the encoder worker and a sink worker. Control messages have priority.
 *
 * Backpressure policy (latency over completeness):
 * - Media queue full + incoming keyframe: discard all queued frames, enqueue the keyframe.
 * - Media queue full + incoming delta frame: discard it and every following delta frame until the
 *   next keyframe (a broken reference chain would only produce corrupt pictures); ask for a keyframe.
 * - The first frame enqueued after any drop carries FRAME_DISCONTINUITY.
 */
class FrameQueue(private val mediaCapacity: Int, private val pool: FramePool, private val controlCapacity: Int = 32) {
    private val lock = ReentrantLock()
    private val notEmpty = lock.newCondition()
    private val control = ArrayDeque<Outbound>()
    private val media = ArrayDeque<Outbound.Frame>()
    private var awaitingKeyframe = false
    private var discontinuity = false

    fun offerControl(o: Outbound): Boolean = lock.withLock {
        if (control.size >= controlCapacity) return false
        control.addLast(o)
        notEmpty.signal()
        true
    }

    fun offerFrame(f: EncodedFrame): OfferResult = lock.withLock {
        if (awaitingKeyframe && !f.isKeyframe) {
            pool.release(f)
            return OfferResult(1, false)
        }
        var dropped = 0
        if (media.size >= mediaCapacity) {
            if (f.isKeyframe) {
                dropped = media.size
                media.forEach { pool.release(it.frame) }
                media.clear()
            } else {
                pool.release(f)
                awaitingKeyframe = true
                discontinuity = true
                return OfferResult(1, true)
            }
            discontinuity = true
        }
        if (f.isKeyframe) awaitingKeyframe = false
        if (discontinuity) {
            f.flags = f.flags or ProtocolV1.FRAME_DISCONTINUITY
            discontinuity = false
        }
        media.addLast(Outbound.Frame(f))
        notEmpty.signal()
        OfferResult(dropped, false)
    }

    /** Blocks up to [timeoutMs]; returns null on timeout. */
    fun poll(timeoutMs: Long): Outbound? = lock.withLock {
        var nanos = TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        while (control.isEmpty() && media.isEmpty()) {
            if (nanos <= 0L) return null
            nanos = notEmpty.awaitNanos(nanos)
        }
        control.pollFirst() ?: media.pollFirst()
    }

    /** Drops everything and requires the next accepted frame to be a keyframe. */
    fun resetAwaitingKeyframe() = lock.withLock {
        clearLocked()
        awaitingKeyframe = true
    }

    fun clear() = lock.withLock { clearLocked() }

    fun mediaSize() = lock.withLock { media.size }

    private fun clearLocked() {
        media.forEach { pool.release(it.frame) }
        media.clear()
        control.clear()
    }
}
