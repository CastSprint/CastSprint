package com.castsprint.android.encoder

import java.io.ByteArrayOutputStream

/**
 * H.264 bitstream normalization. CastSprint transmits **Annex-B** (start-code prefixed) data:
 * VIDEO_CONFIG carries `00 00 00 01 SPS 00 00 00 01 PPS`, VIDEO_FRAME carries one access unit.
 * MediaCodec AVC encoders are documented to emit Annex-B, but some vendors return csd or
 * buffers without start codes or with 4-byte AVCC length prefixes; those are converted here.
 */
object H264 {
    const val NAL_IDR = 5
    const val NAL_SPS = 7
    const val NAL_PPS = 8
    private val START = byteArrayOf(0, 0, 0, 1)

    fun hasStartCode(b: ByteArray, off: Int, len: Int): Boolean =
        (len >= 3 && b[off] == 0.toByte() && b[off + 1] == 0.toByte() && b[off + 2] == 1.toByte()) ||
            (len >= 4 && b[off] == 0.toByte() && b[off + 1] == 0.toByte() && b[off + 2] == 0.toByte() &&
                b[off + 3] == 1.toByte())

    /** True if [b] parses entirely as 4-byte big-endian length-prefixed NAL units. */
    fun isAvcc(b: ByteArray, off: Int, len: Int): Boolean {
        var p = off
        val end = off + len
        if (len < 5) return false
        while (p < end) {
            if (end - p < 4) return false
            val n = ((b[p].toInt() and 0xFF) shl 24) or ((b[p + 1].toInt() and 0xFF) shl 16) or
                ((b[p + 2].toInt() and 0xFF) shl 8) or (b[p + 3].toInt() and 0xFF)
            if (n <= 0 || n > end - p - 4) return false
            p += 4 + n
        }
        return true
    }

    /**
     * Writes Annex-B form of [src] into [dst] (must have capacity >= len + 4 * nalCount, or
     * len + 4 for raw NAL input). Returns written length, or -1 if [dst] is too small.
     */
    fun toAnnexB(src: ByteArray, off: Int, len: Int, dst: ByteArray): Int {
        if (hasStartCode(src, off, len)) {
            if (dst.size < len) return -1
            System.arraycopy(src, off, dst, 0, len)
            return len
        }
        if (isAvcc(src, off, len)) {
            var p = off
            var w = 0
            val end = off + len
            while (p < end) {
                val n = ((src[p].toInt() and 0xFF) shl 24) or ((src[p + 1].toInt() and 0xFF) shl 16) or
                    ((src[p + 2].toInt() and 0xFF) shl 8) or (src[p + 3].toInt() and 0xFF)
                if (w + 4 + n > dst.size) return -1
                System.arraycopy(START, 0, dst, w, 4)
                System.arraycopy(src, p + 4, dst, w + 4, n)
                w += 4 + n
                p += 4 + n
            }
            return w
        }
        // Single raw NAL unit without any prefix.
        if (dst.size < len + 4) return -1
        System.arraycopy(START, 0, dst, 0, 4)
        System.arraycopy(src, off, dst, 4, len)
        return len + 4
    }

    fun toAnnexB(src: ByteArray): ByteArray {
        val dst = ByteArray(src.size + 4 * (src.size / 5 + 1))
        val n = toAnnexB(src, 0, src.size, dst)
        return dst.copyOf(n)
    }

    /** Calls [block] with (nalType, payloadOffset, payloadEndExclusive) for each NAL in Annex-B data. */
    inline fun forEachNal(b: ByteArray, len: Int, block: (type: Int, start: Int, end: Int) -> Unit) {
        var i = 0
        var nalStart = -1
        while (i + 2 < len) {
            if (b[i] == 0.toByte() && b[i + 1] == 0.toByte() && b[i + 2] == 1.toByte()) {
                if (nalStart >= 0) {
                    var e = i
                    while (e > nalStart && b[e - 1] == 0.toByte()) e--
                    block(b[nalStart].toInt() and 0x1F, nalStart, e)
                }
                nalStart = i + 3
                i += 3
            } else {
                i++
            }
        }
        if (nalStart in 0 until len) block(b[nalStart].toInt() and 0x1F, nalStart, len)
    }

    fun containsIdr(b: ByteArray, len: Int): Boolean {
        var found = false
        forEachNal(b, len) { t, _, _ -> if (t == NAL_IDR) found = true }
        return found
    }

    /** Returns (profile_idc, level_idc) from the first SPS, or null. */
    fun profileLevel(annexB: ByteArray): Pair<Int, Int>? {
        var result: Pair<Int, Int>? = null
        forEachNal(annexB, annexB.size) { t, s, e ->
            if (result == null && t == NAL_SPS && e - s >= 4)
                result = (annexB[s + 1].toInt() and 0xFF) to (annexB[s + 3].toInt() and 0xFF)
        }
        return result
    }

    /** Extracts SPS+PPS NAL units (Annex-B) from an access unit, or null if either is missing. */
    fun extractParameterSets(b: ByteArray, len: Int): ByteArray? {
        val out = ByteArrayOutputStream()
        var sps = false
        var pps = false
        forEachNal(b, len) { t, s, e ->
            if (t == NAL_SPS || t == NAL_PPS) {
                out.write(START)
                out.write(b, s, e - s)
                if (t == NAL_SPS) sps = true else pps = true
            }
        }
        return if (sps && pps) out.toByteArray() else null
    }

    /** Builds the VIDEO_CONFIG csd from MediaFormat csd-0 / csd-1 buffers in any supported form. */
    fun buildConfig(csd0: ByteArray, csd1: ByteArray?): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(toAnnexB(csd0))
        if (csd1 != null && csd1.isNotEmpty()) out.write(toAnnexB(csd1))
        return out.toByteArray()
    }
}
