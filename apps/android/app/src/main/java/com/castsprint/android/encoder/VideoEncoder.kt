package com.castsprint.android.encoder

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import com.castsprint.android.diag.EncoderStats
import com.castsprint.android.protocol.ProtocolV1
import com.castsprint.android.transport.FramePool
import com.castsprint.android.transport.FrameQueue
import com.castsprint.android.transport.Outbound
import com.castsprint.android.transport.VideoConfigInfo
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

class VideoEncoder(
    val config: EncoderConfig,
    private val frameQueue: FrameQueue,
    private val pool: FramePool,
    private val stats: EncoderStats,
    private val onFatalError: (Throwable) -> Unit,
) {
    companion object {
        private const val TAG = "VideoEncoder"
        private const val DEQUEUE_TIMEOUT_US = 10_000L
    }

    private var codec: MediaCodec? = null
    private var inputSurface: Surface? = null
    private var workerThread: Thread? = null
    private val isRunning = AtomicBoolean(false)
    private var currentConfigId = 1
    private var lastConfigSent: VideoConfigInfo? = null
    private var rawBuffer = ByteArray(2 * 1024 * 1024)
    private var annexBBuffer = ByteArray(2 * 1024 * 1024)

    val surface: Surface
        get() = inputSurface ?: throw IllegalStateException("Encoder not prepared")

    fun start() {
        if (isRunning.get()) return
        Log.i(TAG, "Starting encoder ${config.codecName} (${config.width}x${config.height} @ ${config.fps}fps, ${config.bitrateBps / 1000}kbps)")

        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, config.width, config.height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, config.bitrateBps)
            setInteger(
                MediaFormat.KEY_BITRATE_MODE,
                if (config.useCbr) MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR
                else MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR
            )
            setInteger(MediaFormat.KEY_FRAME_RATE, config.fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2) // 2 seconds between keyframes
            setInteger(MediaFormat.KEY_PRIORITY, 0) // Realtime priority

            // Keep pipeline producing frames even if static (100ms repeat interval)
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 100_000L)

            if (config.useHighProfile) {
                setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileHigh)
                setInteger(MediaFormat.KEY_LEVEL, MediaCodecInfo.CodecProfileLevel.AVCLevel41)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                setInteger(MediaFormat.KEY_LATENCY, 0)
            }
        }

        val mediaCodec = MediaCodec.createByCodecName(config.codecName)
        try {
            mediaCodec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            inputSurface = mediaCodec.createInputSurface()
            mediaCodec.start()
            codec = mediaCodec
        } catch (e: Throwable) {
            mediaCodec.release()
            inputSurface?.release()
            inputSurface = null
            throw e
        }

        isRunning.set(true)
        workerThread = Thread({ drainLoop() }, "CastSprint-EncoderWorker").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    fun requestKeyframe() {
        val c = codec ?: return
        if (!isRunning.get()) return
        try {
            val params = Bundle().apply {
                putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
            }
            c.setParameters(params)
            Log.d(TAG, "Sync frame requested")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to request sync frame: ${e.message}")
        }
    }

    fun setBitrate(bitrateBps: Int) {
        val c = codec ?: return
        if (!isRunning.get()) return
        try {
            val params = Bundle().apply {
                putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, bitrateBps)
            }
            c.setParameters(params)
            Log.i(TAG, "Bitrate updated to ${bitrateBps / 1000} kbps")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to update bitrate: ${e.message}")
        }
    }

    private fun drainLoop() {
        val bufferInfo = MediaCodec.BufferInfo()
        val c = codec ?: return

        while (isRunning.get()) {
            val outputIndex = try {
                c.dequeueOutputBuffer(bufferInfo, DEQUEUE_TIMEOUT_US)
            } catch (e: Throwable) {
                if (isRunning.get()) {
                    Log.e(TAG, "dequeueOutputBuffer failed", e)
                    onFatalError(e)
                }
                break
            }

            when (outputIndex) {
                MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    // Timeout, keep looping
                }
                MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    handleOutputFormatChanged(c.outputFormat)
                }
                else -> {
                    if (outputIndex >= 0) {
                        try {
                            handleOutputBuffer(c, outputIndex, bufferInfo)
                        } catch (e: Throwable) {
                            Log.e(TAG, "handleOutputBuffer failed", e)
                            if (isRunning.get()) onFatalError(e)
                            break
                        } finally {
                            try {
                                c.releaseOutputBuffer(outputIndex, false)
                            } catch (e: Exception) {
                                Log.w(TAG, "releaseOutputBuffer error: ${e.message}")
                            }
                        }
                    }
                }
            }
        }
    }

    private fun handleOutputFormatChanged(format: MediaFormat) {
        Log.i(TAG, "Encoder output format changed: $format")
        val csd0 = format.getByteBuffer("csd-0")?.let { toByteArray(it) } ?: ByteArray(0)
        val csd1 = format.getByteBuffer("csd-1")?.let { toByteArray(it) }
        val csdCombined = H264.buildConfig(csd0, csd1)
        if (csdCombined.isNotEmpty()) {
            emitVideoConfig(csdCombined)
        }
    }

    private fun handleOutputBuffer(c: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
        val buf = c.getOutputBuffer(index) ?: return
        buf.position(info.offset)
        buf.limit(info.offset + info.size)

        val isConfig = (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
        val isKeyframeFlag = (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0
        val isEos = (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0

        if (info.size > rawBuffer.size) {
            rawBuffer = ByteArray(info.size + 64 * 1024)
        }
        buf.get(rawBuffer, 0, info.size)

        if (isConfig) {
            val annexB = H264.toAnnexB(rawBuffer.copyOf(info.size))
            emitVideoConfig(annexB)
            return
        }

        // If csd has not been received yet, check if this keyframe contains SPS/PPS
        if (lastConfigSent == null) {
            val spsPps = H264.extractParameterSets(rawBuffer, info.size)
            if (spsPps != null) {
                emitVideoConfig(spsPps)
            }
        }

        val requiredAnnexBCapacity = info.size + 64 * 1024
        if (annexBBuffer.size < requiredAnnexBCapacity) {
            annexBBuffer = ByteArray(requiredAnnexBCapacity)
        }

        val annexBLen = H264.toAnnexB(rawBuffer, 0, info.size, annexBBuffer)
        if (annexBLen <= 0 && !isEos) {
            Log.w(TAG, "Failed to convert access unit to Annex-B")
            return
        }

        val isIdr = H264.containsIdr(annexBBuffer, annexBLen)
        val isKey = isKeyframeFlag || isIdr

        var flags = 0
        if (isKey) flags = flags or ProtocolV1.FRAME_KEYFRAME
        if (isEos) flags = flags or ProtocolV1.FRAME_END_OF_STREAM

        stats.onFrame(annexBLen, isKey)

        val frame = pool.acquire(annexBLen)
        System.arraycopy(annexBBuffer, 0, frame.data, 0, annexBLen)
        frame.length = annexBLen
        frame.ptsUs = info.presentationTimeUs
        frame.flags = flags
        frame.configId = currentConfigId

        val offer = frameQueue.offerFrame(frame)
        if (offer.dropped > 0) {
            stats.onDropped(offer.dropped)
        }
        if (offer.keyframeNeeded) {
            requestKeyframe()
        }
    }

    private fun emitVideoConfig(csd: ByteArray) {
        val (profile, level) = H264.profileLevel(csd) ?: (66 to 31)
        val info = VideoConfigInfo(
            configId = currentConfigId,
            profile = profile,
            level = level,
            width = config.width,
            height = config.height,
            fps = config.fps,
            bitrate = config.bitrateBps,
            csd = csd
        )
        lastConfigSent = info
        frameQueue.offerControl(Outbound.Config(info))
        Log.i(TAG, "Emitted VideoConfig id=$currentConfigId (profile=$profile, level=$level, ${csd.size} bytes CSD)")
    }

    private fun toByteArray(byteBuffer: ByteBuffer): ByteArray {
        val b = ByteArray(byteBuffer.remaining())
        val duplicate = byteBuffer.duplicate()
        duplicate.get(b)
        return b
    }

    fun stopAndRelease() {
        if (!isRunning.compareAndSet(true, false)) return
        Log.i(TAG, "Stopping encoder...")

        workerThread?.let {
            it.interrupt()
            try {
                it.join(1000)
            } catch (ignored: InterruptedException) {}
        }
        workerThread = null

        try {
            codec?.stop()
        } catch (e: Exception) {
            Log.w(TAG, "MediaCodec.stop failed: ${e.message}")
        }

        try {
            codec?.release()
        } catch (e: Exception) {
            Log.w(TAG, "MediaCodec.release failed: ${e.message}")
        }
        codec = null

        try {
            inputSurface?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Surface.release failed: ${e.message}")
        }
        inputSurface = null

        Log.i(TAG, "Encoder stopped and released")
    }
}
