package com.castsprint.android.capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import com.castsprint.android.MainActivity
import com.castsprint.android.audio.AudioCaptureEngine
import com.castsprint.android.audio.AudioFrameQueue
import com.castsprint.android.audio.AudioPacket
import com.castsprint.android.diag.EncoderStats
import com.castsprint.android.encoder.CaptureSettings
import com.castsprint.android.encoder.EncoderConfigSelector
import com.castsprint.android.encoder.MediaCodecCapabilitiesQuery
import com.castsprint.android.encoder.OutputMode
import com.castsprint.android.encoder.Resolution
import com.castsprint.android.encoder.Selection
import com.castsprint.android.encoder.VideoEncoder
import com.castsprint.android.protocol.ProtocolV1
import com.castsprint.android.security.PairingInfo
import com.castsprint.android.session.CastSprintSession
import com.castsprint.android.session.Phase
import com.castsprint.android.transport.FileTransportSink
import com.castsprint.android.transport.FramePool
import com.castsprint.android.transport.FrameQueue
import com.castsprint.android.transport.Outbound
import com.castsprint.android.transport.TcpTransportSink
import com.castsprint.android.transport.TransportSink
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ScreenCaptureService : Service() {
    companion object {
        private const val TAG = "ScreenCaptureService"
        const val ACTION_START = "com.castsprint.android.action.START"
        const val ACTION_STOP = "com.castsprint.android.action.STOP"

        const val EXTRA_RESULT_CODE = "extra_result_code"
        const val EXTRA_RESULT_DATA = "extra_result_data"
        const val EXTRA_RESOLUTION = "extra_resolution"
        const val EXTRA_FPS = "extra_fps"
        const val EXTRA_BITRATE = "extra_bitrate"
        const val EXTRA_OUTPUT_MODE = "extra_output_mode"
        const val EXTRA_AUDIO_ENABLED = "extra_audio_enabled"
        const val EXTRA_AUDIO_DELAY_MS = "extra_audio_delay_ms"
        const val EXTRA_PAIRING_HOST = "extra_pairing_host"
        const val EXTRA_PAIRING_PORT = "extra_pairing_port"
        const val EXTRA_PAIRING_FP = "extra_pairing_fp"
        const val EXTRA_PAIRING_TOKEN = "extra_pairing_token"
        const val EXTRA_DISPLAY_WIDTH = "extra_display_width"
        const val EXTRA_DISPLAY_HEIGHT = "extra_display_height"
        const val EXTRA_DENSITY_DPI = "extra_density_dpi"

        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "castsprint_capture_channel"
    }

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var videoEncoder: VideoEncoder? = null
    private var audioCaptureEngine: AudioCaptureEngine? = null
    private var audioFrameQueue: AudioFrameQueue? = null
    private var transportSink: TransportSink? = null
    private var thermalListener: PowerManager.OnThermalStatusChangedListener? = null
    private var stats: EncoderStats? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: return START_NOT_STICKY

        when (action) {
            ACTION_START -> handleStart(intent)
            ACTION_STOP -> handleStop()
        }

        return START_NOT_STICKY
    }

    private fun handleStart(intent: Intent) {
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
        val resultData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(EXTRA_RESULT_DATA)
        }

        if (resultCode == 0 || resultData == null) {
            Log.e(TAG, "Missing MediaProjection consent intent or result code")
            CastSprintSession.transition(Phase.ERROR, error = "Screen capture consent token is missing")
            stopSelf()
            return
        }

        val resOrdinal = intent.getIntExtra(EXTRA_RESOLUTION, Resolution.FHD_1080.ordinal)
        val resolution = Resolution.entries.getOrElse(resOrdinal) { Resolution.FHD_1080 }
        val fps = intent.getIntExtra(EXTRA_FPS, 60)
        val bitrate = intent.getIntExtra(EXTRA_BITRATE, 12_000_000)
        val outputOrdinal = intent.getIntExtra(EXTRA_OUTPUT_MODE, OutputMode.USB_RECEIVER.ordinal)
        val outputMode = OutputMode.entries.getOrElse(outputOrdinal) { OutputMode.USB_RECEIVER }
        val displayW = intent.getIntExtra(EXTRA_DISPLAY_WIDTH, 1080)
        val displayH = intent.getIntExtra(EXTRA_DISPLAY_HEIGHT, 1920)
        val densityDpi = intent.getIntExtra(EXTRA_DENSITY_DPI, 420)

        val audioEnabled = intent.getBooleanExtra(EXTRA_AUDIO_ENABLED, true)
        val audioDelayMs = intent.getIntExtra(EXTRA_AUDIO_DELAY_MS, 0)
        val pairingHost = intent.getStringExtra(EXTRA_PAIRING_HOST)
        val pairingPort = intent.getIntExtra(EXTRA_PAIRING_PORT, ProtocolV1.DEFAULT_PORT)
        val pairingFp = intent.getStringExtra(EXTRA_PAIRING_FP)
        val pairingToken = intent.getStringExtra(EXTRA_PAIRING_TOKEN)

        val settings = CaptureSettings(
            resolution = resolution,
            fps = fps,
            bitrateBps = bitrate,
            output = outputMode,
            audioEnabled = audioEnabled,
            audioDelayMs = audioDelayMs
        )

        // Android 14+ requirement: startForeground MUST be called before getMediaProjection
        val notification = buildNotification(outputMode)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        CastSprintSession.transition(Phase.STARTING, "Configuring hardware encoder...")

        // Query codecs & select config
        val codecs = MediaCodecCapabilitiesQuery.queryH264Encoders()
        val selection = EncoderConfigSelector.select(displayW, displayH, settings, codecs)
        if (selection !is Selection.Ok) {
            val reason = (selection as Selection.Failed).reason
            Log.e(TAG, "Encoder selection failed: $reason")
            CastSprintSession.transition(Phase.ERROR, error = reason)
            stopCapture()
            return
        }

        val config = selection.config
        Log.i(TAG, "Selected encoder: ${config.codecName} (${config.width}x${config.height} @ ${config.fps}fps, hardware=${config.isHardware})")
        CastSprintSession.update {
            it.copy(
                encoderName = config.codecName,
                encoderDetail = "${config.width}x${config.height} @ ${config.fps}fps, ${config.bitrateBps / 1000}kbps" +
                    if (selection.downgradeNote != null) " (${selection.downgradeNote})" else ""
            )
        }

        // Initialize queues, pool and stats
        val pool = FramePool(16)
        val queue = FrameQueue(mediaCapacity = 8, pool = pool)
        val encoderStats = EncoderStats()
        stats = encoderStats
        CastSprintSession.stats = encoderStats

        val audioQueue = if (audioEnabled) AudioFrameQueue(16) else null
        audioFrameQueue = audioQueue

        // Initialize Transport Sink
        val sink: TransportSink = when (outputMode) {
            OutputMode.USB_RECEIVER -> {
                TcpTransportSink(
                    host = "127.0.0.1",
                    port = ProtocolV1.DEFAULT_PORT,
                    frameQueue = queue,
                    pool = pool,
                    stats = encoderStats,
                    displayWidth = displayW,
                    displayHeight = displayH,
                    densityDpi = densityDpi,
                    onKeyframeRequested = { videoEncoder?.requestKeyframe() },
                    pairingInfo = null,
                    sessionToken = pairingToken.orEmpty(),
                    audioQueue = audioQueue
                )
            }
            OutputMode.WIFI_RECEIVER -> {
                val host = pairingHost ?: "127.0.0.1"
                val pInfo = if (!pairingFp.isNullOrEmpty() && !pairingToken.isNullOrEmpty()) {
                    PairingInfo(host, pairingPort, pairingFp, pairingToken)
                } else null
                TcpTransportSink(
                    host = host,
                    port = pairingPort,
                    frameQueue = queue,
                    pool = pool,
                    stats = encoderStats,
                    displayWidth = displayW,
                    displayHeight = displayH,
                    densityDpi = densityDpi,
                    onKeyframeRequested = { videoEncoder?.requestKeyframe() },
                    pairingInfo = pInfo,
                    audioQueue = audioQueue
                )
            }
            OutputMode.H264_FILE -> {
                val timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
                val dir = getExternalFilesDir(null) ?: filesDir
                val file = File(dir, "castsprint_${timeStamp}.h264")
                FileTransportSink(
                    outputFile = file,
                    frameQueue = queue,
                    pool = pool,
                    stats = encoderStats
                )
            }
        }
        transportSink = sink
        sink.start()

        // Initialize VideoEncoder
        val encoder = VideoEncoder(
            config = config,
            frameQueue = queue,
            pool = pool,
            stats = encoderStats,
            onFatalError = { error ->
                Log.e(TAG, "Fatal encoder error", error)
                CastSprintSession.transition(Phase.ERROR, error = "Encoder error: ${error.message}")
                stopCapture()
            }
        )
        try {
            encoder.start()
            videoEncoder = encoder
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VideoEncoder", e)
            CastSprintSession.transition(Phase.ERROR, error = "Failed to start encoder: ${e.message}")
            stopCapture()
            return
        }

        // Initialize MediaProjection
        val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val projection = mpManager.getMediaProjection(resultCode, resultData)
        if (projection == null) {
            Log.e(TAG, "MediaProjection token rejected or already consumed")
            CastSprintSession.transition(Phase.ERROR, error = "MediaProjection consent token was rejected")
            stopCapture()
            return
        }
        mediaProjection = projection

        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                Log.i(TAG, "MediaProjection callback: capture stopped by system or user")
                stopCapture()
            }
        }, null)

        // Start AudioPlaybackCapture if enabled
        if (audioEnabled) {
            try {
                val audioEngine = AudioCaptureEngine(
                    mediaProjection = projection,
                    sampleRate = 48000,
                    channelCount = 2,
                    bitrateBps = 128000,
                    onAudioConfig = { sampleRate, channels, csd ->
                        queue.offerControl(Outbound.AudioConfig(ProtocolV1.AUDIO_CODEC_AAC, channels, sampleRate, csd))
                    },
                    onAudioFrame = { ptsUs, data ->
                        audioQueue?.offer(AudioPacket(ptsUs, data))
                    },
                    onError = { msg, _ ->
                        Log.w(TAG, "Audio capture warning: $msg")
                    }
                )
                if (audioEngine.start()) {
                    audioCaptureEngine = audioEngine
                    Log.i(TAG, "Game audio capture active (48kHz AAC-LC stereo)")
                }
            } catch (t: Throwable) {
                Log.w(TAG, "Failed to start audio capture: ${t.message}")
            }
        }

        // Create VirtualDisplay
        try {
            virtualDisplay = projection.createVirtualDisplay(
                "CastSprint-Display",
                config.width,
                config.height,
                densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                encoder.surface,
                null,
                null
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create VirtualDisplay", e)
            CastSprintSession.transition(Phase.ERROR, error = "VirtualDisplay error: ${e.message}")
            stopCapture()
            return
        }

        // Register thermal listener on API 29+
        registerThermalListener(config.bitrateBps)

        CastSprintSession.transition(Phase.CAPTURING, "Mirroring screen")
        Log.i(TAG, "Capture session active")
    }

    private fun registerThermalListener(baseBitrate: Int) {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val listener = PowerManager.OnThermalStatusChangedListener { status ->
            stats?.thermalStatus = status
            when (status) {
                PowerManager.THERMAL_STATUS_SEVERE, PowerManager.THERMAL_STATUS_CRITICAL -> {
                    Log.w(TAG, "Thermal throttling detected (status $status). Reducing bitrate.")
                    stats?.bitrateReduced = true
                    videoEncoder?.setBitrate((baseBitrate * 0.6).toInt())
                }
                PowerManager.THERMAL_STATUS_NONE, PowerManager.THERMAL_STATUS_LIGHT -> {
                    if (stats?.bitrateReduced == true) {
                        Log.i(TAG, "Thermal status normalized. Restoring base bitrate.")
                        stats?.bitrateReduced = false
                        videoEncoder?.setBitrate(baseBitrate)
                    }
                }
            }
        }
        pm.addThermalStatusListener(listener)
        thermalListener = listener
    }

    private fun handleStop() {
        Log.i(TAG, "Stop request received")
        stopCapture()
    }

    private fun stopCapture() {
        CastSprintSession.transition(Phase.STOPPING, "Stopping mirror...")

        thermalListener?.let {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.removeThermalStatusListener(it)
            thermalListener = null
        }

        try {
            virtualDisplay?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing VirtualDisplay: ${e.message}")
        }
        virtualDisplay = null

        try {
            audioCaptureEngine?.stop()
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping AudioCaptureEngine: ${e.message}")
        }
        audioCaptureEngine = null
        audioFrameQueue = null

        try {
            videoEncoder?.stopAndRelease()
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing VideoEncoder: ${e.message}")
        }
        videoEncoder = null

        try {
            transportSink?.stop()
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping transport: ${e.message}")
        }
        transportSink = null

        try {
            mediaProjection?.stop()
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping MediaProjection: ${e.message}")
        }
        mediaProjection = null

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()

        CastSprintSession.transition(Phase.IDLE, "Mirroring stopped")
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "CastSprint Screen Mirroring",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Active screen capture notification"
            setShowBadge(false)
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(mode: OutputMode): Notification {
        val openIntent = Intent(this, MainActivity::class.java)
        val openPendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, ScreenCaptureService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val content = if (mode == OutputMode.USB_RECEIVER) {
            "Mirroring screen to CastSprint Receiver (USB / LAN)"
        } else {
            "Recording diagnostic H.264 stream"
        }

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("CastSprint Active")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentIntent(openPendingIntent)
            .addAction(
                Notification.Action.Builder(
                    null,
                    "Stop Mirroring",
                    stopPendingIntent
                ).build()
            )
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        stopCapture()
        super.onDestroy()
    }
}
