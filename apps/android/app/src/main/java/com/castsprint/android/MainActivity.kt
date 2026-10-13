package com.castsprint.android

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import com.castsprint.android.capture.CaptureController
import com.castsprint.android.discovery.DiscoveredDevice
import com.castsprint.android.discovery.LanDiscovery
import com.castsprint.android.encoder.CaptureSettings
import com.castsprint.android.encoder.MediaCodecCapabilitiesQuery
import com.castsprint.android.encoder.OutputMode
import com.castsprint.android.encoder.Resolution
import com.castsprint.android.encoder.StreamPreset
import com.castsprint.android.protocol.ProtocolV1
import com.castsprint.android.security.PairingInfo
import com.castsprint.android.security.TlsPinningSocketFactory
import com.castsprint.android.session.CastSprintSession
import com.castsprint.android.session.LinkState
import com.castsprint.android.session.Phase
import com.castsprint.android.session.SessionSnapshot

class MainActivity : Activity() {

    private var selectedResolution = Resolution.FHD_1080
    private var selectedFps = 60
    private var selectedBitrateMbps = 12
    private var selectedOutputMode = OutputMode.USB_RECEIVER
    private var selectedPreset = StreamPreset.BALANCED
    private var audioEnabled = true
    private var pairingInfo: PairingInfo? = null

    private lateinit var prefs: SharedPreferences
    private var lanDiscovery: LanDiscovery? = null

    private lateinit var statusBadge: TextView
    private lateinit var statusDetailText: TextView
    private lateinit var encoderInfoText: TextView
    private lateinit var diagnosticsCard: LinearLayout
    private lateinit var diagFpsText: TextView
    private lateinit var diagBitrateText: TextView
    private lateinit var diagFramesText: TextView
    private lateinit var diagDroppedText: TextView
    private lateinit var diagDurationText: TextView
    private lateinit var diagFileText: TextView
    private lateinit var startButton: Button
    private lateinit var stopButton: Button

    private lateinit var presetButtons: List<Button>
    private lateinit var resButtons: List<Button>
    private lateinit var fpsButtons: List<Button>
    private lateinit var bitrateButtons: List<Button>
    private lateinit var modeButtons: List<Button>
    private lateinit var audioToggleButton: Button
    private lateinit var wifiConfigCard: LinearLayout
    private lateinit var wifiReceiverDetailText: TextView

    private val mainHandler = Handler(Looper.getMainLooper())
    private val statsUpdater = object : Runnable {
        override fun run() {
            updateDiagnostics()
            mainHandler.postDelayed(this, 500)
        }
    }

    private val REQUEST_CAPTURE_CODE = 2001
    private val REQUEST_NOTIF_CODE = 2002

    private val sessionListener: (SessionSnapshot) -> Unit = { snapshot ->
        updateSessionUI(snapshot)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        prefs = getSharedPreferences("castsprint_prefs", Context.MODE_PRIVATE)
        loadSavedPairing()
        audioEnabled = prefs.getBoolean("audio_enabled", true)

        requestNotificationPermissionIfNeeded()
        setupUI()

        CastSprintSession.addListener(sessionListener)
    }

    override fun onResume() {
        super.onResume()
        updateSessionUI(CastSprintSession.machine.snapshot())
        mainHandler.post(statsUpdater)
    }

    override fun onPause() {
        super.onPause()
        mainHandler.removeCallbacks(statsUpdater)
        lanDiscovery?.stopDiscovery()
    }

    override fun onDestroy() {
        CastSprintSession.removeListener(sessionListener)
        lanDiscovery?.stopDiscovery()
        super.onDestroy()
    }

    private fun loadSavedPairing() {
        val host = prefs.getString("pairing_host", null)
        val port = prefs.getInt("pairing_port", ProtocolV1.DEFAULT_PORT)
        val fp = prefs.getString("pairing_fp", null)
        val token = prefs.getString("pairing_token", null)
        val name = prefs.getString("pairing_name", "Windows PC") ?: "Windows PC"
        if (!host.isNullOrEmpty() && !fp.isNullOrEmpty() && !token.isNullOrEmpty()) {
            pairingInfo = PairingInfo(host, port, fp, token, name)
        }
    }

    private fun savePairing(info: PairingInfo) {
        pairingInfo = info
        prefs.edit()
            .putString("pairing_host", info.host)
            .putInt("pairing_port", info.port)
            .putString("pairing_fp", info.fingerprintSha256)
            .putString("pairing_token", info.sessionToken)
            .putString("pairing_name", info.receiverName)
            .apply()
        updateWifiCardDisplay()
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIF_CODE)
            }
        }
    }

    private fun startCaptureFlow() {
        if (CastSprintSession.machine.snapshot().phase != Phase.IDLE &&
            CastSprintSession.machine.snapshot().phase != Phase.ERROR) {
            return
        }

        if (selectedOutputMode == OutputMode.WIFI_RECEIVER && pairingInfo == null) {
            Toast.makeText(this, "Please configure Wi-Fi receiver pairing first", Toast.LENGTH_LONG).show()
            showPairingDialog()
            return
        }

        CastSprintSession.transition(Phase.REQUESTING_PERMISSION, "Waiting for screen capture permission...")
        val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val intent = mpManager.createScreenCaptureIntent()
        startActivityForResult(intent, REQUEST_CAPTURE_CODE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CAPTURE_CODE) {
            handleCaptureResult(resultCode, data)
        }
    }

    private fun handleCaptureResult(resultCode: Int, data: Intent?) {
        if (resultCode == RESULT_OK && data != null) {
            val settings = CaptureSettings(
                resolution = selectedResolution,
                fps = selectedFps,
                bitrateBps = selectedBitrateMbps * 1_000_000,
                output = selectedOutputMode,
                audioEnabled = audioEnabled,
                preset = selectedPreset
            )
            val metrics = DisplayMetrics()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val bounds = windowManager.currentWindowMetrics.bounds
                metrics.widthPixels = bounds.width()
                metrics.heightPixels = bounds.height()
                metrics.densityDpi = resources.configuration.densityDpi
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay.getRealMetrics(metrics)
            }
            CaptureController.startCapture(this, resultCode, data, settings, metrics, pairingInfo)
        } else {
            CastSprintSession.transition(Phase.IDLE, "Permission cancelled by user")
        }
    }

    private fun stopCaptureFlow() {
        android.util.Log.i("MainActivity", "stopCaptureFlow invoked")
        CaptureController.stopCapture(this)
    }

    private fun applyPreset(preset: StreamPreset) {
        selectedPreset = preset
        when (preset) {
            StreamPreset.LOW_LATENCY -> {
                selectedResolution = Resolution.HD_720
                selectedFps = 60
                selectedBitrateMbps = 8
            }
            StreamPreset.BALANCED -> {
                selectedResolution = Resolution.FHD_1080
                selectedFps = 60
                selectedBitrateMbps = 12
            }
            StreamPreset.HIGH_QUALITY -> {
                selectedResolution = Resolution.NATIVE
                selectedFps = 60
                selectedBitrateMbps = 20
            }
            StreamPreset.CUSTOM -> {}
        }
        updatePresetButtons()
        syncConfigSelectorsToState()
    }

    private fun updatePresetButtons() {
        val presets = listOf(StreamPreset.LOW_LATENCY, StreamPreset.BALANCED, StreamPreset.HIGH_QUALITY, StreamPreset.CUSTOM)
        val idx = presets.indexOf(selectedPreset)
        updateOptionGroup(presetButtons, if (idx >= 0) idx else 3)
    }

    private fun syncConfigSelectorsToState() {
        val allResolutions = listOf(
            Resolution.HD_720,
            Resolution.FHD_1080,
            Resolution.QHD_1440,
            Resolution.UHD_2160,
            Resolution.NATIVE
        )
        val resIdx = allResolutions.indexOf(selectedResolution)
        if (resIdx >= 0) updateOptionGroup(resButtons, resIdx)

        val fpsIdx = if (selectedFps == 30) 0 else 1
        updateOptionGroup(fpsButtons, fpsIdx)

        val bitrates = listOf(4, 8, 12, 16, 20, 30, 40)
        val bitIdx = bitrates.indexOf(selectedBitrateMbps)
        if (bitIdx >= 0) updateOptionGroup(bitrateButtons, bitIdx)
    }

    private fun updateSessionUI(s: SessionSnapshot) {
        val isCapturing = s.phase == Phase.CAPTURING || s.phase == Phase.STARTING
        startButton.isEnabled = s.phase == Phase.IDLE || s.phase == Phase.ERROR
        stopButton.isEnabled = isCapturing

        startButton.alpha = if (startButton.isEnabled) 1.0f else 0.4f
        stopButton.alpha = if (stopButton.isEnabled) 1.0f else 0.4f

        setSelectorEnabled(!isCapturing)

        when (s.phase) {
            Phase.IDLE -> {
                statusBadge.text = "IDLE"
                statusBadge.setTextColor(Color.parseColor("#94A3B8"))
                statusBadge.background = makeBadgeDrawable("#1E293B", "#334155")
                statusDetailText.text = s.message.ifEmpty { "Ready to mirror" }
                statusDetailText.setTextColor(Color.parseColor("#94A3B8"))
            }
            Phase.REQUESTING_PERMISSION -> {
                statusBadge.text = "PERMISSION"
                statusBadge.setTextColor(Color.parseColor("#F59E0B"))
                statusBadge.background = makeBadgeDrawable("#451A03", "#78350F")
                statusDetailText.text = "Confirm the system prompt to start"
                statusDetailText.setTextColor(Color.parseColor("#FCD34D"))
            }
            Phase.STARTING -> {
                statusBadge.text = "INITIALIZING"
                statusBadge.setTextColor(Color.parseColor("#38BDF8"))
                statusBadge.background = makeBadgeDrawable("#0C4A6E", "#0284C7")
                statusDetailText.text = s.message
                statusDetailText.setTextColor(Color.parseColor("#BAE6FD"))
            }
            Phase.CAPTURING -> {
                statusBadge.text = "MIRRORING"
                statusBadge.setTextColor(Color.parseColor("#10B981"))
                statusBadge.background = makeBadgeDrawable("#064E3B", "#059669")
                val linkInfo = when (s.link) {
                    LinkState.WAITING_FOR_RECEIVER -> "Waiting for receiver (ADB reverse tcp:${ProtocolV1.DEFAULT_PORT})"
                    LinkState.HANDSHAKING -> "Handshaking with receiver..."
                    LinkState.CONNECTED -> "Streaming to PC (${s.linkDetail})"
                    LinkState.WRITING_FILE -> "Recording to file (${s.linkDetail})"
                    LinkState.NONE -> "Active"
                }
                statusDetailText.text = linkInfo
                statusDetailText.setTextColor(Color.parseColor("#6EE7B7"))
            }
            Phase.STOPPING -> {
                statusBadge.text = "STOPPING"
                statusBadge.setTextColor(Color.parseColor("#F59E0B"))
                statusBadge.background = makeBadgeDrawable("#451A03", "#78350F")
                statusDetailText.text = s.message
                statusDetailText.setTextColor(Color.parseColor("#FCD34D"))
            }
            Phase.ERROR -> {
                statusBadge.text = "ERROR"
                statusBadge.setTextColor(Color.parseColor("#EF4444"))
                statusBadge.background = makeBadgeDrawable("#450A0A", "#991B1B")
                statusDetailText.text = s.error ?: s.message
                statusDetailText.setTextColor(Color.parseColor("#FCA5A5"))
            }
        }

        encoderInfoText.text = if (s.encoderName.isNotEmpty()) {
            "Codec: ${s.encoderName}\n${s.encoderDetail}"
        } else {
            "Codec: Not running"
        }

        diagnosticsCard.visibility = if (isCapturing || CastSprintSession.outputPath != null) View.VISIBLE else View.GONE
    }

    private fun updateDiagnostics() {
        val s = CastSprintSession.stats?.snapshot()
        val session = CastSprintSession.machine.snapshot()

        if (s != null && session.phase == Phase.CAPTURING) {
            val durSec = if (session.startedAtElapsedMs > 0) {
                (SystemClock.elapsedRealtime() - session.startedAtElapsedMs) / 1000
            } else 0
            val durStr = String.format("%02d:%02d", durSec / 60, durSec % 60)

            diagFpsText.text = "Encoded FPS: %.1f".format(s.encodedFps)
            diagBitrateText.text = "Bitrate: %.2f Mbps".format(s.encodedBitrateBps / 1_000_000.0)
            diagFramesText.text = "Frames: ${s.framesProduced} (Key: ${s.keyframes})"
            diagDroppedText.text = "Dropped: ${s.framesDropped}"
            diagDurationText.text = "Duration: $durStr"
        }

        CastSprintSession.outputPath?.let { path ->
            diagFileText.visibility = View.VISIBLE
            diagFileText.text = "Output saved: $path"
        } ?: run {
            diagFileText.visibility = View.GONE
        }
    }

    private fun setSelectorEnabled(enabled: Boolean) {
        val displayMetrics = resources.displayMetrics
        val supported = MediaCodecCapabilitiesQuery.getSupportedResolutions(
            displayMetrics.widthPixels,
            displayMetrics.heightPixels
        )
        val allResolutions = listOf(
            Resolution.HD_720,
            Resolution.FHD_1080,
            Resolution.QHD_1440,
            Resolution.UHD_2160,
            Resolution.NATIVE
        )
        presetButtons.forEach {
            it.isEnabled = enabled
            it.alpha = if (enabled) 1.0f else 0.35f
        }
        resButtons.forEachIndexed { idx, btn ->
            btn.isEnabled = enabled
            val isSupported = supported.contains(allResolutions.getOrElse(idx) { Resolution.FHD_1080 })
            btn.alpha = if (!enabled) 0.35f else if (!isSupported) 0.5f else 1.0f
        }
        fpsButtons.forEach {
            it.isEnabled = enabled
            it.alpha = if (enabled) 1.0f else 0.35f
        }
        bitrateButtons.forEach {
            it.isEnabled = enabled
            it.alpha = if (enabled) 1.0f else 0.35f
        }
        modeButtons.forEach {
            it.isEnabled = enabled
            it.alpha = if (enabled) 1.0f else 0.35f
        }
        audioToggleButton.isEnabled = enabled
        audioToggleButton.alpha = if (enabled) 1.0f else 0.35f
    }

    private fun setupUI() {
        val root = ScrollView(this).apply {
            setBackgroundColor(Color.parseColor("#0B0E19"))
            isFillViewport = true
        }

        val pad = (20 * resources.displayMetrics.density).toInt()
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, pad)
        }

        // Header
        val title = TextView(this).apply {
            text = "CastSprint"
            textSize = 28f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
        }
        val subtitle = TextView(this).apply {
            text = "Low-Latency Gaming Mirror & Audio Streaming"
            textSize = 13f
            setTextColor(Color.parseColor("#94A3B8"))
            setPadding(0, 4, 0, (16 * resources.displayMetrics.density).toInt())
        }
        content.addView(title)
        content.addView(subtitle)

        // Status Card
        val statusCard = createCard().apply {
            val row = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            val label = TextView(this@MainActivity).apply {
                text = "SESSION STATUS"
                textSize = 11f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.parseColor("#64748B"))
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            }
            statusBadge = TextView(this@MainActivity).apply {
                text = "IDLE"
                textSize = 12f
                typeface = Typeface.DEFAULT_BOLD
                setPadding(16, 6, 16, 6)
            }
            row.addView(label)
            row.addView(statusBadge)
            addView(row)

            statusDetailText = TextView(this@MainActivity).apply {
                text = "Ready to mirror"
                textSize = 14f
                setPadding(0, 10, 0, 8)
            }
            addView(statusDetailText)

            encoderInfoText = TextView(this@MainActivity).apply {
                text = "Codec: Ready"
                textSize = 12f
                setTextColor(Color.parseColor("#64748B"))
            }
            addView(encoderInfoText)
        }
        content.addView(statusCard)

        // Action Buttons (Start / Stop)
        val actionsLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val p = (16 * resources.displayMetrics.density).toInt()
            setPadding(0, 0, 0, p)
        }

        startButton = Button(this).apply {
            text = "Start Mirroring"
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            background = makeButtonDrawable("#0284C7", "#0369A1", 8)
            setPadding(0, 32, 0, 32)
            setOnClickListener { startCaptureFlow() }
        }
        actionsLayout.addView(startButton)

        stopButton = Button(this).apply {
            text = "Stop Mirroring"
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            background = makeButtonDrawable("#DC2626", "#B91C1C", 8)
            isEnabled = false
            setPadding(0, 32, 0, 32)
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = (10 * resources.displayMetrics.density).toInt()
            }
            layoutParams = lp
            setOnClickListener { stopCaptureFlow() }
        }
        actionsLayout.addView(stopButton)
        content.addView(actionsLayout)

        // Diagnostics Card
        diagnosticsCard = createCard().apply {
            visibility = View.GONE
            addView(createSectionLabel("LIVE ENCODER DIAGNOSTICS"))
            val grid = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(0, 8, 0, 0)
            }
            diagFpsText = createDiagText()
            diagBitrateText = createDiagText()
            diagFramesText = createDiagText()
            diagDroppedText = createDiagText()
            diagDurationText = createDiagText()
            diagFileText = createDiagText().apply {
                setTextColor(Color.parseColor("#38BDF8"))
                visibility = View.GONE
            }
            grid.addView(diagFpsText)
            grid.addView(diagBitrateText)
            grid.addView(diagFramesText)
            grid.addView(diagDroppedText)
            grid.addView(diagDurationText)
            grid.addView(diagFileText)
            addView(grid)
        }
        content.addView(diagnosticsCard)

        // Presets Section
        content.addView(createSectionLabel("STREAMING PRESETS"))
        val presetRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        presetButtons = listOf(
            createOptionButton("Low Latency", selectedPreset == StreamPreset.LOW_LATENCY) {
                applyPreset(StreamPreset.LOW_LATENCY)
            },
            createOptionButton("Balanced", selectedPreset == StreamPreset.BALANCED) {
                applyPreset(StreamPreset.BALANCED)
            },
            createOptionButton("High Quality", selectedPreset == StreamPreset.HIGH_QUALITY) {
                applyPreset(StreamPreset.HIGH_QUALITY)
            },
            createOptionButton("Custom", selectedPreset == StreamPreset.CUSTOM) {
                selectedPreset = StreamPreset.CUSTOM
                updatePresetButtons()
            }
        )
        presetButtons.forEach { presetRow.addView(it) }
        content.addView(presetRow)

        // Game Audio Capture Toggle
        content.addView(createSectionLabel("GAME AUDIO STREAMING"))
        val audioRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        audioToggleButton = Button(this).apply {
            text = if (audioEnabled) "Game Audio: ON (48kHz AAC)" else "Game Audio: OFF"
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            layoutParams = lp
            applyAudioToggleStyle(this, audioEnabled)
            setOnClickListener {
                audioEnabled = !audioEnabled
                prefs.edit().putBoolean("audio_enabled", audioEnabled).apply()
                text = if (audioEnabled) "Game Audio: ON (48kHz AAC)" else "Game Audio: OFF"
                applyAudioToggleStyle(this, audioEnabled)
            }
        }
        audioRow.addView(audioToggleButton)
        content.addView(audioRow)

        val audioNote = TextView(this).apply {
            text = "AudioPlaybackCapture (Android 10+): Captures games and media. Protected apps disallowing capture remain silent. Microphone is never accessed."
            textSize = 11f
            setTextColor(Color.parseColor("#64748B"))
            setPadding(0, 4, 0, (12 * resources.displayMetrics.density).toInt())
        }
        content.addView(audioNote)

        // Destination Mode Section
        content.addView(createSectionLabel("CONNECTION / TRANSPORT"))
        val modeRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        modeButtons = listOf(
            createOptionButton("USB (ADB reverse)", selectedOutputMode == OutputMode.USB_RECEIVER) {
                selectedOutputMode = OutputMode.USB_RECEIVER
                updateOptionGroup(modeButtons, 0)
                wifiConfigCard.visibility = View.GONE
            },
            createOptionButton("Secure Wi-Fi (LAN)", selectedOutputMode == OutputMode.WIFI_RECEIVER) {
                selectedOutputMode = OutputMode.WIFI_RECEIVER
                updateOptionGroup(modeButtons, 1)
                wifiConfigCard.visibility = View.VISIBLE
                updateWifiCardDisplay()
            },
            createOptionButton("Save File (Diag)", selectedOutputMode == OutputMode.H264_FILE) {
                selectedOutputMode = OutputMode.H264_FILE
                updateOptionGroup(modeButtons, 2)
                wifiConfigCard.visibility = View.GONE
            }
        )
        modeButtons.forEach { modeRow.addView(it) }
        content.addView(modeRow)

        // Wi-Fi Receiver Pairing Card
        wifiConfigCard = createCard().apply {
            visibility = if (selectedOutputMode == OutputMode.WIFI_RECEIVER) View.VISIBLE else View.GONE
            addView(createSectionLabel("WI-FI RECEIVER PAIRING"))

            wifiReceiverDetailText = TextView(this@MainActivity).apply {
                textSize = 13f
                setTextColor(Color.parseColor("#E2E8F0"))
                setPadding(0, 4, 0, 8)
            }
            addView(wifiReceiverDetailText)

            val pairBtn = Button(this@MainActivity).apply {
                text = "Configure / Discover PC"
                textSize = 13f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.WHITE)
                background = makeButtonDrawable("#1E293B", "#334155", 6)
                setOnClickListener { showPairingDialog() }
            }
            addView(pairBtn)
        }
        content.addView(wifiConfigCard)
        updateWifiCardDisplay()

        // Configuration Section
        content.addView(createSectionLabel("CUSTOM ENCODER SETTINGS"))

        // Resolution Selector
        content.addView(createConfigLabel("Resolution"))
        val displayMetrics = resources.displayMetrics
        val supportedResolutions = MediaCodecCapabilitiesQuery.getSupportedResolutions(
            displayMetrics.widthPixels,
            displayMetrics.heightPixels
        )

        val resRow1 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val resRow2 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = (6 * resources.displayMetrics.density).toInt()
            }
            layoutParams = lp
        }

        val allResolutions = listOf(
            Resolution.HD_720 to "720p",
            Resolution.FHD_1080 to "1080p",
            Resolution.QHD_1440 to "2K",
            Resolution.UHD_2160 to "4K",
            Resolution.NATIVE to "Native"
        )

        resButtons = allResolutions.mapIndexed { idx, (res, label) ->
            val isSupported = supportedResolutions.contains(res)
            val displayLabel = if (isSupported) label else "$label*"
            createOptionButton(displayLabel, selectedResolution == res) {
                selectedResolution = res
                selectedPreset = StreamPreset.CUSTOM
                updatePresetButtons()
                updateOptionGroup(resButtons, idx)
                if (!isSupported) {
                    Toast.makeText(
                        this,
                        "$label is not natively supported by device encoder; fallback will apply.",
                        Toast.LENGTH_SHORT
                    ).show()
                }
            }.apply {
                if (!isSupported) alpha = 0.5f
            }
        }

        resButtons.take(3).forEach { resRow1.addView(it) }
        resButtons.drop(3).forEach { resRow2.addView(it) }
        content.addView(resRow1)
        content.addView(resRow2)

        val resHelpText = TextView(this).apply {
            val supportedNames = supportedResolutions.sortedBy { it.longSide }.joinToString(", ") { it.label }
            val note = if (supportedResolutions.size < allResolutions.size) " (*unsupported will auto-fallback)" else ""
            text = "Supported: $supportedNames$note"
            textSize = 11f
            setTextColor(Color.parseColor("#64748B"))
            val padY = (4 * resources.displayMetrics.density).toInt()
            setPadding(0, padY, 0, (8 * resources.displayMetrics.density).toInt())
        }
        content.addView(resHelpText)

        // FPS Selector
        content.addView(createConfigLabel("Target Frame Rate"))
        val fpsRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fpsButtons = listOf(
            createOptionButton("30 FPS", selectedFps == 30) {
                selectedFps = 30
                selectedPreset = StreamPreset.CUSTOM
                updatePresetButtons()
                updateOptionGroup(fpsButtons, 0)
            },
            createOptionButton("60 FPS", selectedFps == 60) {
                selectedFps = 60
                selectedPreset = StreamPreset.CUSTOM
                updatePresetButtons()
                updateOptionGroup(fpsButtons, 1)
            }
        )
        fpsButtons.forEach { fpsRow.addView(it) }
        content.addView(fpsRow)

        // Bitrate Selector
        content.addView(createConfigLabel("Video Bitrate"))
        val bitRow1 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val bitRow2 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = (6 * resources.displayMetrics.density).toInt()
            }
            layoutParams = lp
        }

        val bitrates = listOf(4, 8, 12, 16, 20, 30, 40)
        bitrateButtons = bitrates.mapIndexed { idx, mbps ->
            createOptionButton("${mbps}M", selectedBitrateMbps == mbps) {
                selectedBitrateMbps = mbps
                selectedPreset = StreamPreset.CUSTOM
                updatePresetButtons()
                updateOptionGroup(bitrateButtons, idx)
            }
        }
        bitrateButtons.take(4).forEach { bitRow1.addView(it) }
        bitrateButtons.drop(4).forEach { bitRow2.addView(it) }
        content.addView(bitRow1)
        content.addView(bitRow2)

        root.addView(content)
        setContentView(root)
    }

    private fun updateWifiCardDisplay() {
        if (!::wifiReceiverDetailText.isInitialized) return
        val info = pairingInfo
        if (info != null) {
            val fpShort = if (info.fingerprintSha256.length > 12) {
                "${info.fingerprintSha256.take(8)}...${info.fingerprintSha256.takeLast(4)}"
            } else info.fingerprintSha256
            wifiReceiverDetailText.text = "Target: ${info.receiverName} (${info.host}:${info.port})\nFingerprint: $fpShort\nPIN: ${info.sessionToken}"
            wifiReceiverDetailText.setTextColor(Color.parseColor("#38BDF8"))
        } else {
            wifiReceiverDetailText.text = "No receiver paired. Click below to scan local network or enter IP and PIN."
            wifiReceiverDetailText.setTextColor(Color.parseColor("#94A3B8"))
        }
    }

    private fun applyAudioToggleStyle(btn: Button, enabled: Boolean) {
        if (enabled) {
            btn.setTextColor(Color.WHITE)
            btn.background = makeButtonDrawable("#059669", "#047857", 6)
        } else {
            btn.setTextColor(Color.parseColor("#94A3B8"))
            btn.background = makeButtonDrawable("#1E293B", "#334155", 6)
        }
    }

    private fun showPairingDialog() {
        val dialogView = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val p = (16 * resources.displayMetrics.density).toInt()
            setPadding(p, p, p, p)
        }

        val hostInput = EditText(this).apply {
            hint = "Receiver IP (e.g. 192.168.1.100)"
            setText(pairingInfo?.host ?: "")
            setTextColor(Color.WHITE)
            setHintTextColor(Color.parseColor("#64748B"))
        }
        val portInput = EditText(this).apply {
            hint = "Port (default 27183)"
            setText((pairingInfo?.port ?: ProtocolV1.DEFAULT_PORT).toString())
            setTextColor(Color.WHITE)
            setHintTextColor(Color.parseColor("#64748B"))
        }
        val pinInput = EditText(this).apply {
            hint = "Session PIN (6 digits from PC)"
            setText(pairingInfo?.sessionToken ?: "")
            setTextColor(Color.WHITE)
            setHintTextColor(Color.parseColor("#64748B"))
        }
        val fpInput = EditText(this).apply {
            hint = "SHA-256 Fingerprint (from PC)"
            setText(pairingInfo?.fingerprintSha256 ?: "")
            setTextColor(Color.WHITE)
            setHintTextColor(Color.parseColor("#64748B"))
        }

        val discoveredTitle = TextView(this).apply {
            text = "Discovered Receivers (mDNS):"
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.parseColor("#38BDF8"))
            setPadding(0, 16, 0, 8)
        }
        val discoveredContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        dialogView.addView(TextView(this).apply {
            text = "Manual Configuration or URI:"
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            setPadding(0, 0, 0, 8)
        })
        dialogView.addView(hostInput)
        dialogView.addView(portInput)
        dialogView.addView(pinInput)
        dialogView.addView(fpInput)
        dialogView.addView(discoveredTitle)
        dialogView.addView(discoveredContainer)

        // Start mDNS discovery while dialog is open
        val discovery = LanDiscovery(this).apply {
            onDeviceFound = { dev: DiscoveredDevice ->
                runOnUiThread {
                    val devBtn = Button(this@MainActivity).apply {
                        text = "${dev.name} (${dev.host}:${dev.port})"
                        textSize = 12f
                        setTextColor(Color.WHITE)
                        background = makeButtonDrawable("#1E293B", "#0284C7", 4)
                        setOnClickListener {
                            hostInput.setText(dev.host)
                            portInput.setText(dev.port.toString())
                            if (!dev.fingerprint.isNullOrEmpty()) {
                                fpInput.setText(dev.fingerprint)
                            }
                            Toast.makeText(this@MainActivity, "Selected ${dev.name}", Toast.LENGTH_SHORT).show()
                        }
                    }
                    discoveredContainer.addView(devBtn)
                }
            }
        }
        discovery.startDiscovery()

        AlertDialog.Builder(this)
            .setTitle("Wi-Fi Receiver Pairing")
            .setView(dialogView)
            .setPositiveButton("Save") { _, _ ->
                discovery.stopDiscovery()
                val host = hostInput.text.toString().trim()
                val port = portInput.text.toString().trim().toIntOrNull() ?: ProtocolV1.DEFAULT_PORT
                val token = pinInput.text.toString().trim()
                val fp = TlsPinningSocketFactory.normalizeFingerprint(fpInput.text.toString())
                if (host.isNotEmpty() && token.isNotEmpty() && fp.isNotEmpty()) {
                    savePairing(PairingInfo(host, port, fp, token))
                    Toast.makeText(this, "Wi-Fi Pairing saved", Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(this, "Host, PIN and Fingerprint are required", Toast.LENGTH_LONG).show()
                }
            }
            .setNegativeButton("Cancel") { _, _ ->
                discovery.stopDiscovery()
            }
            .setOnDismissListener {
                discovery.stopDiscovery()
            }
            .show()
    }

    private fun createCard(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        background = makeCardDrawable()
        val p = (16 * resources.displayMetrics.density).toInt()
        setPadding(p, p, p, p)
        val lp = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            bottomMargin = (16 * resources.displayMetrics.density).toInt()
        }
        layoutParams = lp
    }

    private fun createSectionLabel(text: String): TextView = TextView(this).apply {
        this.text = text
        textSize = 12f
        typeface = Typeface.DEFAULT_BOLD
        setTextColor(Color.parseColor("#38BDF8"))
        setPadding(0, (12 * resources.displayMetrics.density).toInt(), 0, (6 * resources.displayMetrics.density).toInt())
    }

    private fun createConfigLabel(text: String): TextView = TextView(this).apply {
        this.text = text
        textSize = 13f
        setTextColor(Color.parseColor("#E2E8F0"))
        setPadding(0, (8 * resources.displayMetrics.density).toInt(), 0, (4 * resources.displayMetrics.density).toInt())
    }

    private fun createDiagText(): TextView = TextView(this).apply {
        textSize = 13f
        setTextColor(Color.parseColor("#94A3B8"))
        setPadding(0, 2, 0, 2)
    }

    private fun createOptionButton(label: String, selected: Boolean, onClick: () -> Unit): Button {
        val btn = Button(this).apply {
            text = label
            textSize = 13f
            typeface = if (selected) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginEnd = 6
                marginStart = 6
            }
            layoutParams = lp
            setOnClickListener { onClick() }
        }
        applyOptionButtonStyle(btn, selected)
        return btn
    }

    private fun updateOptionGroup(buttons: List<Button>, selectedIndex: Int) {
        buttons.forEachIndexed { idx, btn ->
            applyOptionButtonStyle(btn, idx == selectedIndex)
        }
    }

    private fun applyOptionButtonStyle(btn: Button, selected: Boolean) {
        if (selected) {
            btn.setTextColor(Color.WHITE)
            btn.background = makeButtonDrawable("#0284C7", "#0369A1", 6)
        } else {
            btn.setTextColor(Color.parseColor("#94A3B8"))
            btn.background = makeButtonDrawable("#1E293B", "#334155", 6)
        }
    }

    private fun makeCardDrawable() = GradientDrawable().apply {
        setColor(Color.parseColor("#111827"))
        cornerRadius = 16f * resources.displayMetrics.density
        setStroke((1 * resources.displayMetrics.density).toInt(), Color.parseColor("#1F2937"))
    }

    private fun makeBadgeDrawable(bgHex: String, borderHex: String) = GradientDrawable().apply {
        setColor(Color.parseColor(bgHex))
        cornerRadius = 8f * resources.displayMetrics.density
        setStroke((1 * resources.displayMetrics.density).toInt(), Color.parseColor(borderHex))
    }

    private fun makeButtonDrawable(bgHex: String, borderHex: String, radiusDp: Int) = GradientDrawable().apply {
        setColor(Color.parseColor(bgHex))
        cornerRadius = radiusDp * resources.displayMetrics.density
        setStroke((1 * resources.displayMetrics.density).toInt(), Color.parseColor(borderHex))
    }
}
