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
}
