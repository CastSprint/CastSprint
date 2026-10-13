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
        if (caps == null || videoCaps == null) return false
        if (!supportsSurfaceInput()) return false
        return videoCaps.isSizeSupported(width, height) &&
            videoCaps.areSizeAndRateSupported(width, height, fps.toDouble())
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
}
