package com.castsprint.android.session

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.castsprint.android.diag.EncoderStats
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Process-wide session holder shared by the UI and [com.castsprint.android.capture.ScreenCaptureService].
 * Listeners are always invoked on the main thread.
 */
object CastSprintSession {
    val machine = SessionStateMachine()
    @Volatile var stats: EncoderStats? = null
    @Volatile var outputPath: String? = null

    private val listeners = CopyOnWriteArrayList<(SessionSnapshot) -> Unit>()
    private val main = Handler(Looper.getMainLooper())

    fun addListener(l: (SessionSnapshot) -> Unit) {
        listeners += l
        l(machine.snapshot())
    }

    fun removeListener(l: (SessionSnapshot) -> Unit) {
        listeners -= l
    }

    fun transition(to: Phase, message: String = "", error: String? = null): Boolean {
        val ok = machine.transition(to, message, error, SystemClock.elapsedRealtime())
        if (ok) notifyListeners()
        return ok
    }

    fun update(block: (SessionSnapshot) -> SessionSnapshot) {
        machine.update(block)
        notifyListeners()
    }

    fun reset(message: String = "") {
        machine.reset(message)
        notifyListeners()
    }

    private fun notifyListeners() {
        main.post {
            val s = machine.snapshot()
            listeners.forEach { it(s) }
        }
    }
}
