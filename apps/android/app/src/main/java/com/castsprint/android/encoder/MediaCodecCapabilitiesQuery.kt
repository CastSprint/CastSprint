package com.castsprint.android.encoder

import android.media.MediaCodecInfo
import android.media.MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build

class AndroidCodecCapabilities(private val info: MediaCodecInfo) : CodecCapabilities {
    private val caps: MediaCodecInfo.CodecCapabilities? = runCatching {
        info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
    }.getOrNull()

    private val videoCaps = caps?.videoCapabilities
    private val encoderCaps = caps?.encoderCapabilities

    override val name: String = info.name

    override val isHardware: Boolean = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        info.isHardwareAccelerated
    } else {
        !info.name.startsWith("OMX.google.", ignoreCase = true) &&
            !info.name.startsWith("c2.android.", ignoreCase = true)
    }

    override val widthAlignment: Int = videoCaps?.widthAlignment ?: 16
    override val heightAlignment: Int = videoCaps?.heightAlignment ?: 16

    override val bitrateRange: IntRange = run {
        val range = videoCaps?.bitrateRange
        if (range != null) range.lower..range.upper else 500_000..50_000_000
    }

    override val supportsCbr: Boolean = run {
        encoderCaps?.isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR) ?: false
    }

    override val supportsHighProfile: Boolean = run {
        caps?.profileLevels?.any {
            it.profile == MediaCodecInfo.CodecProfileLevel.AVCProfileHigh
        } ?: false
    }

    fun supportsSurfaceInput(): Boolean = caps?.colorFormats?.contains(COLOR_FormatSurface) == true

    override fun supports(width: Int, height: Int, fps: Int): Boolean {
        val vc = videoCaps ?: return false
        if (!supportsSurfaceInput()) return false
        if (!vc.isSizeSupported(width, height)) return false
        return runCatching {
            vc.areSizeAndRateSupported(width, height, fps.toDouble())
        }.getOrDefault(true)
    }
}

object MediaCodecCapabilitiesQuery {
    fun queryH264Encoders(): List<CodecCapabilities> {
        val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        return codecList.codecInfos
            .filter { it.isEncoder && it.supportedTypes.any { t -> t.equals(MediaFormat.MIMETYPE_VIDEO_AVC, ignoreCase = true) } }
            .map { AndroidCodecCapabilities(it) }
            .filter { it.supportsSurfaceInput() }
    }

    /** Returns which resolutions are supported by at least one available H.264 encoder for the display. */
    fun getSupportedResolutions(displayW: Int, displayH: Int): Set<Resolution> {
        val encoders = queryH264Encoders()
        if (encoders.isEmpty()) return setOf(Resolution.HD_720, Resolution.FHD_1080)

        return Resolution.entries.filter { res ->
            encoders.any { encoder ->
                val (w, h) = EncoderConfigSelector.fitSize(displayW, displayH, res, encoder.widthAlignment, encoder.heightAlignment)
                encoder.supports(w, h, 30)
            }
        }.toSet().ifEmpty {
            setOf(Resolution.HD_720, Resolution.FHD_1080)
        }
    }
}

