package com.castsprint.android.capture

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.DisplayMetrics
import com.castsprint.android.encoder.CaptureSettings

object CaptureController {

    fun startCapture(
        context: Context,
        resultCode: Int,
        resultData: Intent,
        settings: CaptureSettings,
        metrics: DisplayMetrics,
    ) {
        val intent = Intent(context, ScreenCaptureService::class.java).apply {
            action = ScreenCaptureService.ACTION_START
            putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
            putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, resultData)
            putExtra(ScreenCaptureService.EXTRA_RESOLUTION, settings.resolution.ordinal)
            putExtra(ScreenCaptureService.EXTRA_FPS, settings.fps)
            putExtra(ScreenCaptureService.EXTRA_BITRATE, settings.bitrateBps)
            putExtra(ScreenCaptureService.EXTRA_OUTPUT_MODE, settings.output.ordinal)
            putExtra(ScreenCaptureService.EXTRA_DISPLAY_WIDTH, metrics.widthPixels)
            putExtra(ScreenCaptureService.EXTRA_DISPLAY_HEIGHT, metrics.heightPixels)
            putExtra(ScreenCaptureService.EXTRA_DENSITY_DPI, metrics.densityDpi)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    fun stopCapture(context: Context) {
        val intent = Intent(context, ScreenCaptureService::class.java).apply {
            action = ScreenCaptureService.ACTION_STOP
        }
        context.startService(intent)
    }
}
