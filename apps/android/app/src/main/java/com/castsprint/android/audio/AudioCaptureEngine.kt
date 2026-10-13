package com.castsprint.android.audio

import android.annotation.SuppressLint
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.os.Build
import android.util.Log
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Captures game and media playback audio using Android 10+ AudioPlaybackCapture API
 * and encodes it to AAC-LC using hardware/software MediaCodec.
 *
 * Requirements:
 * - Android 10+ (API 29+).
 * - MediaProjection user grant.
 * - Respects system policies: apps with ALLOW_CAPTURE_BY_NONE produce silence without failing.
 * - Emits monotonic PTS microseconds synchronized with video stream monotonic clock.
 */
class AudioCaptureEngine(
    private val mediaProjection: MediaProjection,
    private val sampleRate: Int = DEFAULT_SAMPLE_RATE,
    private val channelCount: Int = DEFAULT_CHANNELS,
    private val bitrateBps: Int = DEFAULT_BITRATE,
    private val onAudioConfig: (sampleRate: Int, channels: Int, csd: ByteArray) -> Unit,
    private val onAudioFrame: (ptsUs: Long, data: ByteArray) -> Unit,
    private val onError: (String, Throwable?) -> Unit,
) {
    companion object {
        private const val TAG = "AudioCaptureEngine"
        const val DEFAULT_SAMPLE_RATE = 48000
        const val DEFAULT_CHANNELS = 2
        const val DEFAULT_BITRATE = 128000
        private const val TIMEOUT_US = 10000L
    }

    private val isRunning = AtomicBoolean(false)
    private var workerThread: Thread? = null

    private var audioRecord: AudioRecord? = null
    private var encoder: MediaCodec? = null

    @SuppressLint("MissingPermission")
    fun start(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            Log.w(TAG, "Audio playback capture requires Android 10+ (API 29+)")
            onError("Audio playback capture requires Android 10+", null)
            return false
        }
        if (isRunning.getAndSet(true)) {
            Log.w(TAG, "Audio capture engine already running")
            return true
        }

        try {
            // 1. Configure AudioPlaybackCaptureConfiguration
            val captureConfig = AudioPlaybackCaptureConfiguration.Builder(mediaProjection)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .build()

            val channelMask = if (channelCount == 1) AudioFormat.CHANNEL_IN_MONO else AudioFormat.CHANNEL_IN_STEREO
            val encoding = AudioFormat.ENCODING_PCM_16BIT

            val minBufSize = AudioRecord.getMinBufferSize(sampleRate, channelMask, encoding)
            val bufferSize = maxOf(minBufSize * 2, sampleRate * channelCount * 2 / 10) // ~100ms

            val audioFormat = AudioFormat.Builder()
                .setEncoding(encoding)
                .setSampleRate(sampleRate)
                .setChannelMask(channelMask)
                .build()

            val record = AudioRecord.Builder()
                .setAudioPlaybackCaptureConfig(captureConfig)
                .setAudioFormat(audioFormat)
                .setBufferSizeInBytes(bufferSize)
                .build()

            if (record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                throw IllegalStateException("AudioRecord initialization failed (state=${record.state})")
            }
            audioRecord = record

            // 2. Configure MediaCodec AAC-LC encoder
            val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            val mediaFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channelCount).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, bitrateBps)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    setInteger(MediaFormat.KEY_PRIORITY, 0)
                }
            }
            codec.configure(mediaFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            encoder = codec

            record.startRecording()

            workerThread = Thread({ captureAndEncodeLoop() }, "CS-AudioCapture").apply {
                priority = Thread.MAX_PRIORITY
                start()
            }
            Log.i(TAG, "Audio capture engine started ($sampleRate Hz, $channelCount ch, $bitrateBps bps)")
            return true
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to start AudioCaptureEngine", t)
            cleanup()
            isRunning.set(false)
            onError("Failed to initialize audio capture: ${t.message}", t)
            return false
        }
    }

    fun stop() {
        if (!isRunning.getAndSet(false)) return
        Log.i(TAG, "Stopping audio capture engine...")
        workerThread?.interrupt()
        workerThread?.join(1000)
        workerThread = null
        cleanup()
        Log.i(TAG, "Audio capture engine stopped")
    }

    private fun captureAndEncodeLoop() {
        val record = audioRecord ?: return
        val codec = encoder ?: return

        // 1024 samples per frame * 2 channels * 2 bytes per sample = 4096 bytes per AAC frame chunk
        val pcmChunkSize = 2048 * channelCount
        val pcmBuffer = ByteArray(pcmChunkSize)
        val bufferInfo = MediaCodec.BufferInfo()

        try {
            while (isRunning.get() && !Thread.currentThread().isInterrupted) {
                // Read PCM from AudioPlaybackCapture
                val bytesRead = record.read(pcmBuffer, 0, pcmBuffer.size)
                if (bytesRead <= 0) {
                    if (bytesRead < 0) {
                        Log.w(TAG, "AudioRecord read returned error code $bytesRead")
                    }
                    Thread.sleep(5)
                    continue
                }

                // Monotonic PTS in microseconds aligned with system nanotime
                val ptsUs = System.nanoTime() / 1000L

                // Feed into MediaCodec input buffer
                val inputIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                if (inputIndex >= 0) {
                    val inputBuffer = codec.getInputBuffer(inputIndex)
                    if (inputBuffer != null) {
                        inputBuffer.clear()
                        inputBuffer.put(pcmBuffer, 0, bytesRead)
                        codec.queueInputBuffer(inputIndex, 0, bytesRead, ptsUs, 0)
                    }
                }

                // Drain MediaCodec output buffers
                drainEncoder(codec, bufferInfo)
            }
        } catch (ignored: InterruptedException) {
            // Expected on stop
        } catch (t: Throwable) {
            if (isRunning.get()) {
                Log.e(TAG, "Error in audio capture loop", t)
                onError("Audio capture error: ${t.message}", t)
            }
        }
    }

    private fun drainEncoder(codec: MediaCodec, bufferInfo: MediaCodec.BufferInfo) {
        while (isRunning.get()) {
            val outputIndex = codec.dequeueOutputBuffer(bufferInfo, 0)
            if (outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                break
            } else if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val newFormat = codec.outputFormat
                val csd0 = newFormat.getByteBuffer("csd-0")
                if (csd0 != null) {
                    val csdBytes = ByteArray(csd0.remaining())
                    csd0.get(csdBytes)
                    Log.i(TAG, "Audio codec format changed: CSD length=${csdBytes.size} bytes")
                    onAudioConfig(sampleRate, channelCount, csdBytes)
                }
            } else if (outputIndex >= 0) {
                val outputBuffer = codec.getOutputBuffer(outputIndex)
                if (outputBuffer != null && bufferInfo.size > 0) {
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                        // Audio Specific Config CSD
                        val csdBytes = ByteArray(bufferInfo.size)
                        outputBuffer.position(bufferInfo.offset)
                        outputBuffer.get(csdBytes)
                        onAudioConfig(sampleRate, channelCount, csdBytes)
                    } else {
                        // Regular AAC-LC audio frame
                        val frameBytes = ByteArray(bufferInfo.size)
                        outputBuffer.position(bufferInfo.offset)
                        outputBuffer.get(frameBytes)
                        onAudioFrame(bufferInfo.presentationTimeUs, frameBytes)
                    }
                }
                codec.releaseOutputBuffer(outputIndex, false)
            }
        }
    }

    private fun cleanup() {
        try {
            audioRecord?.stop()
        } catch (ignored: Throwable) {}
        try {
            audioRecord?.release()
        } catch (ignored: Throwable) {}
        audioRecord = null

        try {
            encoder?.stop()
        } catch (ignored: Throwable) {}
        try {
            encoder?.release()
        } catch (ignored: Throwable) {}
        encoder = null
    }
}
