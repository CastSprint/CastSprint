package com.castsprint.android.transport

import com.castsprint.android.protocol.ProtocolV1
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FrameQueueTest {

    @Test
    fun framePoolReusesReleasedBuffers() {
        val pool = FramePool(maxPooled = 4)
        val f1 = pool.acquire(1000)
        assertEquals(0, pool.pooledCount())

        pool.release(f1)
        assertEquals(1, pool.pooledCount())

        val f2 = pool.acquire(500)
        assertEquals(0, pool.pooledCount())
        assertTrue(f2.data.size >= 1000) // reused f1's backing array
    }

    @Test
    fun controlMessagesHavePriorityOverFrames() {
        val pool = FramePool()
        val queue = FrameQueue(mediaCapacity = 4, pool = pool)

        val frame = pool.acquire(10).apply {
            length = 10
            flags = ProtocolV1.FRAME_KEYFRAME
        }
        queue.offerFrame(frame)

        val config = VideoConfigInfo(1, 100, 41, 1920, 1080, 60, 10_000_000, byteArrayOf(1, 2, 3))
        queue.offerControl(Outbound.Config(config))

        // Poll should return Control first
        val first = queue.poll(10)
        assertTrue(first is Outbound.Config)
        assertEquals(1, (first as Outbound.Config).info.configId)

        // Then Frame
        val second = queue.poll(10)
        assertTrue(second is Outbound.Frame)
    }

    @Test
    fun dropsDeltaFramesWhenQueueIsFullAndRequestsKeyframe() {
        val pool = FramePool()
        val queue = FrameQueue(mediaCapacity = 2, pool = pool)

        // Add 2 frames (queue full)
        val f1 = pool.acquire(10).apply { flags = ProtocolV1.FRAME_KEYFRAME }
        val f2 = pool.acquire(10).apply { flags = 0 }
        queue.offerFrame(f1)
        queue.offerFrame(f2)
        assertEquals(2, queue.mediaSize())

        // Third frame is delta -> must be dropped and signal keyframeNeeded
        val f3 = pool.acquire(10).apply { flags = 0 }
        val r3 = queue.offerFrame(f3)
        assertEquals(1, r3.dropped)
        assertTrue(r3.keyframeNeeded)
        assertEquals(2, queue.mediaSize())

        // Next delta frame is also dropped while awaiting keyframe
        val f4 = pool.acquire(10).apply { flags = 0 }
        val r4 = queue.offerFrame(f4)
        assertEquals(1, r4.dropped)
        assertFalse(r4.keyframeNeeded)

        // Now incoming keyframe is accepted and clears stale queue
        val f5 = pool.acquire(10).apply { flags = ProtocolV1.FRAME_KEYFRAME }
        val r5 = queue.offerFrame(f5)
        assertEquals(2, r5.dropped) // previous 2 frames dropped
        assertFalse(r5.keyframeNeeded)
        assertEquals(1, queue.mediaSize())

        val polled = queue.poll(10) as Outbound.Frame
        assertTrue(polled.frame.flags and ProtocolV1.FRAME_DISCONTINUITY != 0)
    }
}
