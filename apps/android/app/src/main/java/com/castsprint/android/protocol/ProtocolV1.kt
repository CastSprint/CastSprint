package com.castsprint.android.protocol

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * CastSprint Protocol v1 (sender side). Normative spec: docs/architecture/PROTOCOL.md.
 * Must stay byte-identical with native/protocol (verified by shared golden vectors).
 */
object ProtocolV1 {
    const val MAGIC: Int = 0x43535052 // "CSPR"
    const val VERSION: Int = 1
    const val HEADER_SIZE: Int = 24
    const val MAX_PAYLOAD_SIZE: Int = 8 * 1024 * 1024
    const val MAX_CONTROL_PAYLOAD_SIZE: Int = 64 * 1024
    const val MAX_STRING_BYTES: Int = 256
    const val DEFAULT_PORT: Int = 27183

    const val FRAME_KEYFRAME: Int = 1 shl 0
    const val FRAME_DISCONTINUITY: Int = 1 shl 1
    const val FRAME_END_OF_STREAM: Int = 1 shl 2

    const val CAP_VIDEO_H264: Int = 1 shl 0
    const val CAP_AUDIO: Int = 1 shl 1
    const val CAP_VIDEO_H265: Int = 1 shl 2

    const val AUDIO_CODEC_OPUS: Int = 1
    const val AUDIO_CODEC_AAC: Int = 2
    const val AUDIO_CODEC_PCM16: Int = 3
}

enum class MessageType(val code: Int) {
    HELLO(0x01), HELLO_ACK(0x02),
    VIDEO_CONFIG(0x10), VIDEO_FRAME(0x11),
    AUDIO_CONFIG(0x20), AUDIO_FRAME(0x21),
    DISPLAY_CHANGED(0x30),
    HEARTBEAT(0x40), STATUS(0x41),
    DISCONNECT(0x50), ERROR(0x51);

    val isMedia: Boolean get() = this == VIDEO_FRAME || this == AUDIO_FRAME

    companion object {
        fun fromCode(code: Int): MessageType? = entries.firstOrNull { it.code == code }
    }
}

data class Header(
    val type: MessageType,
    val sessionId: Int,
    val sequence: Int,
    val payloadLength: Int,
)

sealed class HeaderResult {
    data class Ok(val header: Header) : HeaderResult()
    data class Invalid(val reason: String) : HeaderResult()
    data object NeedMoreData : HeaderResult()
}

object ProtocolCodec {

    /** Builds a complete message (header + payload). */
    fun encode(type: MessageType, sessionId: Int, sequence: Int, payload: ByteArray): ByteArray {
        val limit = if (type.isMedia) ProtocolV1.MAX_PAYLOAD_SIZE else ProtocolV1.MAX_CONTROL_PAYLOAD_SIZE
        require(payload.size <= limit) { "payload ${payload.size} exceeds $limit for $type" }
        return ByteBuffer.allocate(ProtocolV1.HEADER_SIZE + payload.size)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(ProtocolV1.MAGIC)
            .put(ProtocolV1.VERSION.toByte())
            .put(type.code.toByte())
            .putShort(0)
            .putInt(sessionId)
            .putInt(sequence)
            .putInt(payload.size)
            .putInt(0)
            .put(payload)
            .array()
    }

    fun decodeHeader(bytes: ByteArray, offset: Int = 0): HeaderResult {
        if (bytes.size - offset < ProtocolV1.HEADER_SIZE) return HeaderResult.NeedMoreData
        val b = ByteBuffer.wrap(bytes, offset, ProtocolV1.HEADER_SIZE).order(ByteOrder.BIG_ENDIAN)
        if (b.int != ProtocolV1.MAGIC) return HeaderResult.Invalid("bad magic")
        val version = b.get().toInt() and 0xFF
        if (version != ProtocolV1.VERSION) return HeaderResult.Invalid("unsupported version $version")
        val type = MessageType.fromCode(b.get().toInt() and 0xFF)
            ?: return HeaderResult.Invalid("unknown type")
        val flags = b.short.toInt()
        val session = b.int
        val seq = b.int
        val len = b.int
        val reserved = b.int
        if (flags != 0 || reserved != 0) return HeaderResult.Invalid("reserved bits set")
        val limit = if (type.isMedia) ProtocolV1.MAX_PAYLOAD_SIZE else ProtocolV1.MAX_CONTROL_PAYLOAD_SIZE
        if (len < 0 || len > limit) return HeaderResult.Invalid("payload too large")
        return HeaderResult.Ok(Header(type, session, seq, len))
    }

    fun heartbeatPayload(timestampMicros: Long, echoTimestampMicros: Long): ByteArray =
        ByteBuffer.allocate(16).order(ByteOrder.BIG_ENDIAN)
            .putLong(timestampMicros).putLong(echoTimestampMicros).array()

    fun helloPayload(
        capabilities: Int,
        apiLevel: Int,
        width: Int,
        height: Int,
        densityDpi: Int,
        deviceName: String,
        deviceModel: String,
    ): ByteArray {
        val name = deviceName.encodeToByteArray()
        val model = deviceModel.encodeToByteArray()
        require(name.size <= ProtocolV1.MAX_STRING_BYTES && model.size <= ProtocolV1.MAX_STRING_BYTES)
        return ByteBuffer.allocate(16 + 2 + name.size + 2 + model.size).order(ByteOrder.BIG_ENDIAN)
            .put(ProtocolV1.VERSION.toByte()).put(ProtocolV1.VERSION.toByte()).putShort(0)
            .putInt(capabilities)
            .putShort(apiLevel.toShort()).putShort(width.toShort())
            .putShort(height.toShort()).putShort(densityDpi.toShort())
            .putShort(name.size.toShort()).put(name)
            .putShort(model.size.toShort()).put(model)
            .array()
    }

    fun videoConfigPayload(
        configId: Int,
        profile: Int,
        level: Int,
        rotation: Int,
        width: Int,
        height: Int,
        fps: Int,
        bitrate: Int,
        csd: ByteArray,
    ): ByteArray {
        val b = ByteBuffer.allocate(24 + csd.size).order(ByteOrder.BIG_ENDIAN)
        b.putInt(configId)
        b.put(1.toByte()) // Codec H.264 = 1
        b.put(profile.toByte())
        b.put(level.toByte())
        b.put(rotation.toByte())
        b.putShort(width.toShort())
        b.putShort(height.toShort())
        b.putShort(fps.toShort())
        b.putShort(0) // reserved
        b.putInt(bitrate)
        b.putInt(csd.size)
        b.put(csd)
        return b.array()
    }

    fun videoFrameHeader(
        sessionId: Int,
        sequence: Int,
        configId: Int,
        frameFlags: Int,
        ptsUs: Long,
        frameLength: Int,
    ): ByteArray {
        val payloadLen = 16 + frameLength
        val b = ByteBuffer.allocate(ProtocolV1.HEADER_SIZE + 16).order(ByteOrder.BIG_ENDIAN)
        b.putInt(ProtocolV1.MAGIC)
        b.put(ProtocolV1.VERSION.toByte())
        b.put(MessageType.VIDEO_FRAME.code.toByte())
        b.putShort(0)
        b.putInt(sessionId)
        b.putInt(sequence)
        b.putInt(payloadLen)
        b.putInt(0)
        b.putInt(configId)
        b.putInt(frameFlags)
        b.putLong(ptsUs)
        return b.array()
    }

    fun audioConfigPayload(
        codec: Int,
        channels: Int,
        sampleRate: Int,
        csd: ByteArray,
    ): ByteArray {
        require(channels in 1..8) { "invalid channels $channels" }
        require(sampleRate > 0) { "invalid sampleRate $sampleRate" }
        require(csd.size <= ProtocolV1.MAX_CONTROL_PAYLOAD_SIZE) { "csd too large" }
        val b = ByteBuffer.allocate(12 + csd.size).order(ByteOrder.BIG_ENDIAN)
        b.put(codec.toByte())
        b.put(channels.toByte())
        b.putShort(0) // reserved
        b.putInt(sampleRate)
        b.putInt(csd.size)
        b.put(csd)
        return b.array()
    }

    fun audioFrameHeader(
        sessionId: Int,
        sequence: Int,
        ptsUs: Long,
        frameLength: Int,
    ): ByteArray {
        val payloadLen = 8 + frameLength
        val b = ByteBuffer.allocate(ProtocolV1.HEADER_SIZE + 8).order(ByteOrder.BIG_ENDIAN)
        b.putInt(ProtocolV1.MAGIC)
        b.put(ProtocolV1.VERSION.toByte())
        b.put(MessageType.AUDIO_FRAME.code.toByte())
        b.putShort(0)
        b.putInt(sessionId)
        b.putInt(sequence)
        b.putInt(payloadLen)
        b.putInt(0)
        b.putLong(ptsUs)
        return b.array()
    }

    fun audioFramePayload(ptsUs: Long, data: ByteArray): ByteArray {
        val b = ByteBuffer.allocate(8 + data.size).order(ByteOrder.BIG_ENDIAN)
        b.putLong(ptsUs)
        b.put(data)
        return b.array()
    }

    data class AudioConfigData(
        val codec: Int,
        val channels: Int,
        val sampleRate: Int,
        val csd: ByteArray,
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is AudioConfigData) return false
            return codec == other.codec && channels == other.channels &&
                sampleRate == other.sampleRate && csd.contentEquals(other.csd)
        }

        override fun hashCode(): Int {
            var result = codec
            result = 31 * result + channels
            result = 31 * result + sampleRate
            result = 31 * result + csd.contentHashCode()
            return result
        }
    }

    fun decodeAudioConfig(payload: ByteArray): AudioConfigData? {
        if (payload.size < 12) return null
        val b = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
        val codec = b.get().toInt() and 0xFF
        val channels = b.get().toInt() and 0xFF
        val reserved = b.short.toInt()
        if (reserved != 0) return null
        val sampleRate = b.int
        val csdLen = b.int
        if (csdLen < 0 || payload.size < 12 + csdLen) return null
        val csd = ByteArray(csdLen)
        b.get(csd)
        return AudioConfigData(codec, channels, sampleRate, csd)
    }

    data class AudioFrameData(
        val ptsUs: Long,
        val data: ByteArray,
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is AudioFrameData) return false
            return ptsUs == other.ptsUs && data.contentEquals(other.data)
        }

        override fun hashCode(): Int {
            var result = ptsUs.hashCode()
            result = 31 * result + data.contentHashCode()
            return result
        }
    }

    fun decodeAudioFrame(payload: ByteArray): AudioFrameData? {
        if (payload.size < 8) return null
        val b = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
        val ptsUs = b.long
        val data = ByteArray(payload.size - 8)
        b.get(data)
        return AudioFrameData(ptsUs, data)
    }

    fun displayChangedPayload(width: Int, height: Int, rotation: Int, nextConfigId: Int): ByteArray {
        val b = ByteBuffer.allocate(12).order(ByteOrder.BIG_ENDIAN)
        b.putShort(width.toShort())
        b.putShort(height.toShort())
        b.put(rotation.toByte())
        b.put(0.toByte())
        b.putShort(0)
        b.putInt(nextConfigId)
        return b.array()
    }

    fun disconnectPayload(reason: Int, message: String): ByteArray {
        val m = message.encodeToByteArray()
        val len = m.size.coerceAtMost(ProtocolV1.MAX_STRING_BYTES)
        val b = ByteBuffer.allocate(2 + 2 + len).order(ByteOrder.BIG_ENDIAN)
        b.putShort(reason.toShort())
        b.putShort(len.toShort())
        b.put(m, 0, len)
        return b.array()
    }

    data class HelloAckData(
        val status: Int,
        val acceptedVersion: Int,
        val sessionId: Int,
        val maxPayloadSize: Int,
    )

    fun decodeHelloAck(payload: ByteArray): HelloAckData? {
        if (payload.size < 12) return null
        val b = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
        val status = b.get().toInt() and 0xFF
        val acceptedVersion = b.get().toInt() and 0xFF
        val reserved = b.short.toInt()
        if (reserved != 0) return null
        val sessionId = b.int
        val maxPayload = b.int
        return HelloAckData(status, acceptedVersion, sessionId, maxPayload)
    }
}
