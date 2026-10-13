package com.castsprint.android.protocol

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ProtocolCodecTest {

    // Same golden vector as tests/protocol/protocol_tests.cpp (TestGoldenHeartbeat).
    private val goldenHeartbeat = byteArrayOf(
        0x43, 0x53, 0x50, 0x52, 0x01, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00,
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
    )

    @Test
    fun heartbeatMatchesNativeGoldenVector() {
        val payload = ProtocolCodec.heartbeatPayload(0x0102030405060708L, 0x1112131415161718L)
        val bytes = ProtocolCodec.encode(MessageType.HEARTBEAT, 1, 2, payload)
        assertArrayEquals(goldenHeartbeat, bytes)
    }

    @Test
    fun headerRoundTrip() {
        val r = ProtocolCodec.decodeHeader(goldenHeartbeat)
        assertEquals(HeaderResult.Ok(Header(MessageType.HEARTBEAT, 1, 2, 16)), r)
    }

    @Test
    fun rejectsInvalidHeaders() {
        assertEquals(HeaderResult.NeedMoreData, ProtocolCodec.decodeHeader(goldenHeartbeat.copyOf(23)))
        val badMagic = goldenHeartbeat.copyOf().also { it[0] = 0 }
        assertTrue(ProtocolCodec.decodeHeader(badMagic) is HeaderResult.Invalid)
        val badVersion = goldenHeartbeat.copyOf().also { it[4] = 2 }
        assertTrue(ProtocolCodec.decodeHeader(badVersion) is HeaderResult.Invalid)
        val badType = goldenHeartbeat.copyOf().also { it[5] = 0x7F }
        assertTrue(ProtocolCodec.decodeHeader(badType) is HeaderResult.Invalid)
        val reserved = goldenHeartbeat.copyOf().also { it[23] = 1 }
        assertTrue(ProtocolCodec.decodeHeader(reserved) is HeaderResult.Invalid)
        val tooBig = goldenHeartbeat.copyOf().also { it[17] = 0x01; it[19] = 0x01 }
        assertTrue(ProtocolCodec.decodeHeader(tooBig) is HeaderResult.Invalid)
    }

    @Test
    fun helloLayout() {
        val p = ProtocolCodec.helloPayload(ProtocolV1.CAP_VIDEO_H264, 34, 1080, 2400, 420, "Pixel", "x")
        assertEquals(16 + 2 + 5 + 2 + 1, p.size)
        assertEquals(1, p[0].toInt())
        assertEquals(1, p[1].toInt())
    }

    @Test
    fun audioConfigRoundTrip() {
        val csd = byteArrayOf(0x11, 0x90.toByte()) // AAC-LC 48kHz stereo
        val payload = ProtocolCodec.audioConfigPayload(ProtocolV1.AUDIO_CODEC_AAC, 2, 48000, csd)
        val decoded = ProtocolCodec.decodeAudioConfig(payload)
        assertEquals(ProtocolCodec.AudioConfigData(ProtocolV1.AUDIO_CODEC_AAC, 2, 48000, csd), decoded)
    }

    @Test
    fun audioFrameRoundTrip() {
        val aacData = byteArrayOf(0x21, 0x43, 0x65, 0x87.toByte())
        val payload = ProtocolCodec.audioFramePayload(123456789L, aacData)
        val decoded = ProtocolCodec.decodeAudioFrame(payload)
        assertEquals(ProtocolCodec.AudioFrameData(123456789L, aacData), decoded)
    }
}
