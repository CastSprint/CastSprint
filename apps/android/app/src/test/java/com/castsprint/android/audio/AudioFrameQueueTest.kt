package com.castsprint.android.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioFrameQueueTest {

    @Test
    fun testOfferAndPoll() {
        val queue = AudioFrameQueue(4)
        assertEquals(0, queue.size)

        val p1 = AudioPacket(1000, byteArrayOf(1, 2, 3))
        val p2 = AudioPacket(2000, byteArrayOf(4, 5, 6))

        assertTrue(queue.offer(p1))
        assertTrue(queue.offer(p2))
        assertEquals(2, queue.size)

        val polled1 = queue.poll(10)
        assertNotNull(polled1)
        assertEquals(1000L, polled1!!.ptsUs)

        val polled2 = queue.poll(10)
        assertNotNull(polled2)
        assertEquals(2000L, polled2!!.ptsUs)

        assertEquals(0, queue.size)
        assertNull(queue.poll(5))
    }

    @Test
    fun testCapacityEviction() {
        val queue = AudioFrameQueue(2)

        val p1 = AudioPacket(1000, byteArrayOf(1))
        val p2 = AudioPacket(2000, byteArrayOf(2))
        val p3 = AudioPacket(3000, byteArrayOf(3))

        queue.offer(p1)
        queue.offer(p2)
        assertEquals(2, queue.size)

        // Third packet should evict the oldest (p1) to prevent latency buildup
        queue.offer(p3)
        assertEquals(2, queue.size)

        val polled = queue.poll(10)
        assertNotNull(polled)
        assertEquals(2000L, polled!!.ptsUs)

        val polled2 = queue.poll(10)
        assertNotNull(polled2)
        assertEquals(3000L, polled2!!.ptsUs)
    }

    @Test
    fun testClear() {
        val queue = AudioFrameQueue(4)
        queue.offer(AudioPacket(1000, byteArrayOf(1)))
        queue.offer(AudioPacket(2000, byteArrayOf(2)))
        assertEquals(2, queue.size)

        queue.clear()
        assertEquals(0, queue.size)
        assertNull(queue.poll(5))
    }
}
