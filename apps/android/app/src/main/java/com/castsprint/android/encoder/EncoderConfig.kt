package com.castsprint.android.encoder

import kotlin.math.max
import kotlin.math.min

enum class Resolution(val label: String, val longSide: Int, val shortSide: Int) {
    HD_720("720p", 1280, 720),
    FHD_1080("1080p", 1920, 1080),
    QHD_1440("2K", 2560, 1440),
    UHD_2160("4K", 3840, 2160),
    NATIVE("Native", 10_000, 10_000);

    companion object {
        fun fromOrdinal(ordinal: Int): Resolution =
            entries.getOrElse(ordinal) { FHD_1080 }
    }
}

enum class OutputMode { USB_RECEIVER, H264_FILE }

data class CaptureSettings(
    val resolution: Resolution,
    val fps: Int,
    val bitrateBps: Int,
    val output: OutputMode,
) {
    companion object {
        val FPS_OPTIONS = listOf(30, 60)
        val BITRATE_OPTIONS_MBPS = listOf(4, 8, 12, 16, 20, 30, 40)
        const val MIN_BITRATE = 500_000
        const val MAX_BITRATE = 100_000_000
    }

    fun validate(): String? = when {
        fps !in FPS_OPTIONS -> "Unsupported FPS $fps"
        bitrateBps !in MIN_BITRATE..MAX_BITRATE -> "Bitrate out of range"
        else -> null
    }
}

/** Read-only view of one encoder's capabilities (lets selection logic run in JVM tests). */
interface CodecCapabilities {
    val name: String
    val isHardware: Boolean
    val widthAlignment: Int
    val heightAlignment: Int
    val bitrateRange: IntRange
    val supportsCbr: Boolean
    val supportsHighProfile: Boolean
    fun supports(width: Int, height: Int, fps: Int): Boolean
}

data class EncoderConfig(
    val codecName: String,
    val isHardware: Boolean,
    val width: Int,
    val height: Int,
    val fps: Int,
    val bitrateBps: Int,
    val useCbr: Boolean,
    val useHighProfile: Boolean,
)

sealed class Selection {
    data class Ok(val config: EncoderConfig, val downgradeNote: String?) : Selection()
    data class Failed(val reason: String) : Selection()
}

object EncoderConfigSelector {

    /** Scales display dims to fit within the resolution box, preserving aspect and orientation. */
    fun fitSize(displayW: Int, displayH: Int, res: Resolution, alignW: Int, alignH: Int): Pair<Int, Int> {
        require(displayW > 0 && displayH > 0) { "invalid display size" }
        val portrait = displayH >= displayW
        val boxW = if (portrait) res.shortSide else res.longSide
        val boxH = if (portrait) res.longSide else res.shortSide
        val scale = min(1.0, min(boxW.toDouble() / displayW, boxH.toDouble() / displayH))
        val aw = max(2, alignW)
        val ah = max(2, alignH)
        val w = max(aw, ((displayW * scale).toInt() / aw) * aw)
        val h = max(ah, ((displayH * scale).toInt() / ah) * ah)
        return w to h
    }

    /**
     * Picks the first (codec, resolution, fps) combination that the codec reports as supported.
     * Order: requested -> lower fps -> lower resolution -> both; hardware codecs before software.
     */
    fun select(displayW: Int, displayH: Int, settings: CaptureSettings, codecs: List<CodecCapabilities>): Selection {
        settings.validate()?.let { return Selection.Failed(it) }
        if (displayW <= 0 || displayH <= 0) return Selection.Failed("Invalid display size ${displayW}x$displayH")
        if (codecs.isEmpty()) return Selection.Failed("No H.264 encoder available on this device")

        val ordered = codecs.sortedByDescending { it.isHardware }
        val attempts = buildList {
            add(settings.resolution to settings.fps)
            if (settings.fps > 30) add(settings.resolution to 30)
            Resolution.entries.filter { it.longSide < settings.resolution.longSide }
                .sortedByDescending { it.longSide }
                .forEach { r ->
                    add(r to settings.fps)
                    if (settings.fps > 30) add(r to 30)
                }
        }
        for ((res, fps) in attempts) {
            for (c in ordered) {
                val (w, h) = fitSize(displayW, displayH, res, c.widthAlignment, c.heightAlignment)
                if (!c.supports(w, h, fps)) continue
                val bitrate = settings.bitrateBps.coerceIn(c.bitrateRange.first, c.bitrateRange.last)
                val cfg = EncoderConfig(c.name, c.isHardware, w, h, fps, bitrate, c.supportsCbr, c.supportsHighProfile)
                val notes = buildList {
                    if (res != settings.resolution || fps != settings.fps)
                        add("${settings.resolution.label}${settings.fps} unsupported; using ${res.label}$fps")
                    if (bitrate != settings.bitrateBps) add("bitrate clamped to ${bitrate / 1000} kbps")
                    if (!c.isHardware) add("software encoder")
                }
                return Selection.Ok(cfg, notes.joinToString("; ").ifEmpty { null })
            }
        }
        return Selection.Failed("No encoder supports ${settings.resolution.label}${settings.fps} or any fallback")
    }
}
