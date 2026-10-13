package com.castsprint.android

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
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
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.castsprint.android.capture.CaptureController
import com.castsprint.android.encoder.CaptureSettings
import com.castsprint.android.encoder.OutputMode
import com.castsprint.android.encoder.Resolution
import com.castsprint.android.protocol.ProtocolV1
import com.castsprint.android.session.CastSprintSession
import com.castsprint.android.session.LinkState
import com.castsprint.android.session.Phase
import com.castsprint.android.session.SessionSnapshot

class MainActivity : Activity() {

    private var selectedResolution = Resolution.FHD_1080
    private var selectedFps = 60
    private var selectedBitrateMbps = 12
    private var selectedOutputMode = OutputMode.USB_RECEIVER

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

    private lateinit var resButtons: List<Button>
    private lateinit var fpsButtons: List<Button>
    private lateinit var bitrateButtons: List<Button>
    private lateinit var modeButtons: List<Button>

    private val mainHandler = Handler(Looper.getMainLooper())
    private val statsUpdater = object : Runnable {
        override fun run() {
            updateDiagnostics()
            mainHandler.postDelayed(this, 500)
        }
    }

    private val REQUEST_CAPTURE_CODE = 2001
    private val REQUEST_NOTIF_CODE = 2002

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        requestNotificationPermissionIfNeeded()
        setupUI()

        CastSprintSession.addListener { snapshot ->
            updateSessionUI(snapshot)
        }
    }

    override fun onResume() {
        super.onResume()
        mainHandler.post(statsUpdater)
    }

    override fun onPause() {
        super.onPause()
        mainHandler.removeCallbacks(statsUpdater)
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
                output = selectedOutputMode
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
            CaptureController.startCapture(this, resultCode, data, settings, metrics)
        } else {
            CastSprintSession.transition(Phase.IDLE, "Permission cancelled by user")
        }
    }

    private fun stopCaptureFlow() {
        CaptureController.stopCapture(this)
    }

    private fun updateSessionUI(s: SessionSnapshot) {
        val isCapturing = s.phase == Phase.CAPTURING || s.phase == Phase.STARTING
        startButton.isEnabled = s.phase == Phase.IDLE || s.phase == Phase.ERROR
        stopButton.isEnabled = isCapturing

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
        resButtons.forEach { it.isEnabled = enabled }
        fpsButtons.forEach { it.isEnabled = enabled }
        bitrateButtons.forEach { it.isEnabled = enabled }
        modeButtons.forEach { it.isEnabled = enabled }
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
            text = "Professional Low-Latency Android Screen Mirroring"
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

        // Configuration Section
        content.addView(createSectionLabel("MIRRORING SETTINGS"))

        // Resolution Selector
        content.addView(createConfigLabel("Resolution"))
        val resRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        resButtons = listOf(
            createOptionButton("720p", selectedResolution == Resolution.HD_720) {
                selectedResolution = Resolution.HD_720
                updateOptionGroup(resButtons, 0)
            },
            createOptionButton("1080p", selectedResolution == Resolution.FHD_1080) {
                selectedResolution = Resolution.FHD_1080
                updateOptionGroup(resButtons, 1)
            }
        )
        resButtons.forEach { resRow.addView(it) }
        content.addView(resRow)

        // FPS Selector
        content.addView(createConfigLabel("Target Frame Rate"))
        val fpsRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fpsButtons = listOf(
            createOptionButton("30 FPS", selectedFps == 30) {
                selectedFps = 30
                updateOptionGroup(fpsButtons, 0)
            },
            createOptionButton("60 FPS", selectedFps == 60) {
                selectedFps = 60
                updateOptionGroup(fpsButtons, 1)
            }
        )
        fpsButtons.forEach { fpsRow.addView(it) }
        content.addView(fpsRow)

        // Bitrate Selector
        content.addView(createConfigLabel("Video Bitrate"))
        val bitRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val bitrates = listOf(4, 8, 12, 16, 20)
        bitrateButtons = bitrates.mapIndexed { idx, mbps ->
            createOptionButton("${mbps}M", selectedBitrateMbps == mbps) {
                selectedBitrateMbps = mbps
                updateOptionGroup(bitrateButtons, idx)
            }
        }
        bitrateButtons.forEach { bitRow.addView(it) }
        content.addView(bitRow)

        // Output Mode
        content.addView(createConfigLabel("Output Destination"))
        val modeRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        modeButtons = listOf(
            createOptionButton("USB / PC (Protocol)", selectedOutputMode == OutputMode.USB_RECEIVER) {
                selectedOutputMode = OutputMode.USB_RECEIVER
                updateOptionGroup(modeButtons, 0)
            },
            createOptionButton("Save H.264 (Diag)", selectedOutputMode == OutputMode.H264_FILE) {
                selectedOutputMode = OutputMode.H264_FILE
                updateOptionGroup(modeButtons, 1)
            }
        )
        modeButtons.forEach { modeRow.addView(it) }
        content.addView(modeRow)

        root.addView(content)
        setContentView(root)
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
