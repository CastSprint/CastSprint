package com.castsprint.android

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView
import com.castsprint.android.protocol.ProtocolV1

/**
 * Phase 1 launcher screen. Shows build/protocol info only; capture and streaming
 * (MediaProjection + foreground service) are implemented in Phase 2.
 */
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val density = resources.displayMetrics.density
        val pad = (24 * density).toInt()

        fun text(value: String, sizeSp: Float, color: Int, bold: Boolean = false) =
            TextView(this).apply {
                text = value
                textSize = sizeSp
                setTextColor(color)
                gravity = Gravity.CENTER
                if (bold) typeface = Typeface.DEFAULT_BOLD
                setPadding(0, pad / 3, 0, pad / 3)
            }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(pad, pad, pad, pad)
            setBackgroundColor(Color.rgb(11, 14, 25))
            addView(text(getString(R.string.app_name), 34f, Color.WHITE, bold = true))
            addView(text(getString(R.string.tagline), 16f, Color.rgb(160, 174, 210)))
            addView(text(getString(R.string.status_foundation), 14f, Color.rgb(94, 234, 212)))
            addView(
                text(
                    "Protocol v${ProtocolV1.VERSION} · port ${ProtocolV1.DEFAULT_PORT} · " +
                        "Android API ${Build.VERSION.SDK_INT}",
                    12f,
                    Color.rgb(110, 120, 150),
                ),
            )
        }
        setContentView(root)
    }
}
