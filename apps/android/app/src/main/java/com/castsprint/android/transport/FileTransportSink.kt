package com.castsprint.android.transport

import android.util.Log
import com.castsprint.android.diag.EncoderStats
import com.castsprint.android.session.CastSprintSession
import com.castsprint.android.session.LinkState
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean

class FileTransportSink(
    private val outputFile: File,
    private val frameQueue: FrameQueue,
    private val pool: FramePool,
    private val stats: EncoderStats,
) : TransportSink {
    companion object {
        private const val TAG = "FileTransportSink"
    }

    private val isRunning = AtomicBoolean(false)
    private var workerThread: Thread? = null

    override fun start() {
        if (isRunning.get()) return
        isRunning.set(true)

        CastSprintSession.update {
            it.copy(
                link = LinkState.WRITING_FILE,
                linkDetail = outputFile.name
            )
        }

        workerThread = Thread({ runLoop() }, "CastSprint-FileSinkWorker").apply {
            start()
        }
    }

    private fun runLoop() {
        Log.i(TAG, "Writing H.264 stream to ${outputFile.absolutePath}")
        var stream: BufferedOutputStream? = null
        try {
            outputFile.parentFile?.mkdirs()
            stream = BufferedOutputStream(FileOutputStream(outputFile), 256 * 1024)

            while (isRunning.get()) {
                val outbound = frameQueue.poll(100) ?: continue
                when (outbound) {
                    is Outbound.Config -> {
                        stream.write(outbound.info.csd)
                        stream.flush()
                        Log.i(TAG, "Wrote CSD header (${outbound.info.csd.size} bytes)")
                    }
                    is Outbound.Frame -> {
                        val frame = outbound.frame
                        try {
                            stream.write(frame.data, 0, frame.length)
                        } finally {
                            pool.release(frame)
                        }
                    }
                    is Outbound.DisplayChanged -> {
                        Log.i(TAG, "Display changed: ${outbound.width}x${outbound.height}")
                    }
                    is Outbound.Disconnect -> {
                        Log.i(TAG, "Disconnect requested: ${outbound.message}")
                        break
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "File sink error", e)
        } finally {
            try {
                stream?.flush()
                stream?.close()
            } catch (e: Exception) {
                Log.w(TAG, "Error closing file stream", e)
            }
            CastSprintSession.outputPath = outputFile.absolutePath
            Log.i(TAG, "File stream closed. Final size: ${outputFile.length()} bytes")
        }
    }

    override fun stop() {
        if (!isRunning.compareAndSet(true, false)) return
        workerThread?.let {
            it.interrupt()
            try {
                it.join(1000)
            } catch (ignored: InterruptedException) {}
        }
        workerThread = null
    }
}
