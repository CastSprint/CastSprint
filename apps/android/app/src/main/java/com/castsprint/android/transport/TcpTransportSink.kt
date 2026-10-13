package com.castsprint.android.transport

import android.os.Build
import android.os.SystemClock
import android.util.Log
import com.castsprint.android.diag.EncoderStats
import com.castsprint.android.protocol.HeaderResult
import com.castsprint.android.protocol.MessageType
import com.castsprint.android.protocol.ProtocolCodec
import com.castsprint.android.protocol.ProtocolV1
import com.castsprint.android.session.CastSprintSession
import com.castsprint.android.session.LinkState
import java.io.BufferedOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

class TcpTransportSink(
    private val host: String = "127.0.0.1",
    private val port: Int = ProtocolV1.DEFAULT_PORT,
    private val frameQueue: FrameQueue,
    private val pool: FramePool,
    private val stats: EncoderStats,
    private val displayWidth: Int,
    private val displayHeight: Int,
    private val densityDpi: Int,
    private val onKeyframeRequested: () -> Unit,
) : TransportSink {
    companion object {
        private const val TAG = "TcpTransportSink"
        private const val CONNECT_TIMEOUT_MS = 3000
        private const val SO_TIMEOUT_MS = 2000
    }

    private val isRunning = AtomicBoolean(false)
    private var workerThread: Thread? = null
    private var readerThread: Thread? = null
    private var socket: Socket? = null
    private var outStream: OutputStream? = null

    private var sessionId: Int = 0
    private var sequenceOut: Int = 0
    private var lastHeartbeatSentNs: Long = 0L

    override fun start() {
        if (isRunning.get()) return
        isRunning.set(true)

        workerThread = Thread({ runTransport() }, "CastSprint-TcpSender").apply {
            start()
        }
    }

    private fun runTransport() {
        Log.i(TAG, "Starting TCP transport to $host:$port")
        while (isRunning.get()) {
            CastSprintSession.update {
                it.copy(
                    link = LinkState.WAITING_FOR_RECEIVER,
                    linkDetail = "Connecting to $host:$port (ADB reverse)..."
                )
            }

            val s = Socket()
            try {
                s.tcpNoDelay = true
                s.sendBufferSize = 512 * 1024
                s.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
                s.soTimeout = SO_TIMEOUT_MS
                socket = s

                val rawOut = s.getOutputStream()
                val out = BufferedOutputStream(rawOut, 64 * 1024)
                outStream = out
                val inStream = s.getInputStream()

                // Perform Handshake
                CastSprintSession.update {
                    it.copy(link = LinkState.HANDSHAKING, linkDetail = "Sending HELLO...")
                }
                if (!performHandshake(out, inStream)) {
                    closeSocket()
                    sleepBeforeRetry()
                    continue
                }

                CastSprintSession.update {
                    it.copy(link = LinkState.CONNECTED, linkDetail = "Connected (Session $sessionId)")
                }

                startReaderThread(inStream)

                // Sender loop
                while (isRunning.get() && !s.isClosed) {
                    val nowNs = System.nanoTime()
                    if (nowNs - lastHeartbeatSentNs > 1_000_000_000L) {
                        sendHeartbeat(out)
                        lastHeartbeatSentNs = nowNs
                    }

                    val outbound = frameQueue.poll(50) ?: continue
                    when (outbound) {
                        is Outbound.Config -> {
                            val payload = ProtocolCodec.videoConfigPayload(
                                configId = outbound.info.configId,
                                profile = outbound.info.profile,
                                level = outbound.info.level,
                                rotation = 0,
                                width = outbound.info.width,
                                height = outbound.info.height,
                                fps = outbound.info.fps,
                                bitrate = outbound.info.bitrate,
                                csd = outbound.info.csd
                            )
                            val msg = ProtocolCodec.encode(
                                MessageType.VIDEO_CONFIG,
                                sessionId,
                                sequenceOut++,
                                payload
                            )
                            out.write(msg)
                            out.flush()
                        }
                        is Outbound.Frame -> {
                            val f = outbound.frame
                            try {
                                val header = ProtocolCodec.videoFrameHeader(
                                    sessionId = sessionId,
                                    sequence = sequenceOut++,
                                    configId = f.configId,
                                    frameFlags = f.flags,
                                    ptsUs = f.ptsUs,
                                    frameLength = f.length
                                )
                                out.write(header)
                                out.write(f.data, 0, f.length)
                                out.flush()
                            } finally {
                                pool.release(f)
                            }
                        }
                        is Outbound.DisplayChanged -> {
                            val payload = ProtocolCodec.displayChangedPayload(
                                outbound.width,
                                outbound.height,
                                0,
                                outbound.nextConfigId
                            )
                            val msg = ProtocolCodec.encode(
                                MessageType.DISPLAY_CHANGED,
                                sessionId,
                                sequenceOut++,
                                payload
                            )
                            out.write(msg)
                            out.flush()
                        }
                        is Outbound.Disconnect -> {
                            val payload = ProtocolCodec.disconnectPayload(
                                outbound.reason,
                                outbound.message
                            )
                            val msg = ProtocolCodec.encode(
                                MessageType.DISCONNECT,
                                sessionId,
                                sequenceOut++,
                                payload
                            )
                            out.write(msg)
                            out.flush()
                            break
                        }
                    }
                }
            } catch (e: Exception) {
                if (isRunning.get()) {
                    Log.w(TAG, "TCP transport connection broke: ${e.message}")
                }
            } finally {
                closeSocket()
            }

            if (isRunning.get()) {
                sleepBeforeRetry()
            }
        }
    }

    private fun performHandshake(out: OutputStream, inStream: InputStream): Boolean {
        val helloPayload = ProtocolCodec.helloPayload(
            capabilities = ProtocolV1.CAP_VIDEO_H264,
            apiLevel = Build.VERSION.SDK_INT,
            width = displayWidth,
            height = displayHeight,
            densityDpi = densityDpi,
            deviceName = Build.MANUFACTURER,
            deviceModel = Build.MODEL
        )
        val helloMsg = ProtocolCodec.encode(MessageType.HELLO, 0, sequenceOut++, helloPayload)
        out.write(helloMsg)
        out.flush()

        // Read 24-byte header for HELLO_ACK
        val headerBuf = ByteArray(ProtocolV1.HEADER_SIZE)
        readFully(inStream, headerBuf)
        val headerResult = ProtocolCodec.decodeHeader(headerBuf)
        if (headerResult !is HeaderResult.Ok || headerResult.header.type != MessageType.HELLO_ACK) {
            Log.e(TAG, "Handshake failed: expected HELLO_ACK, got $headerResult")
            return false
        }

        val payload = ByteArray(headerResult.header.payloadLength)
        readFully(inStream, payload)
        val ack = ProtocolCodec.decodeHelloAck(payload)
        if (ack == null || ack.status != 0) {
            Log.e(TAG, "Receiver rejected HELLO: status=${ack?.status}")
            return false
        }

        sessionId = ack.sessionId
        Log.i(TAG, "Handshake complete. Assigned session ID: $sessionId")
        return true
    }

    private fun sendHeartbeat(out: OutputStream) {
        val nowUs = SystemClock.elapsedRealtimeNanos() / 1000
        val payload = ProtocolCodec.heartbeatPayload(nowUs, 0L)
        val msg = ProtocolCodec.encode(MessageType.HEARTBEAT, sessionId, sequenceOut++, payload)
        out.write(msg)
        out.flush()
    }

    private fun startReaderThread(inStream: InputStream) {
        readerThread = Thread({
            val headerBytes = ByteArray(ProtocolV1.HEADER_SIZE)
            try {
                while (isRunning.get() && socket?.isClosed == false) {
                    readFully(inStream, headerBytes)
                    val r = ProtocolCodec.decodeHeader(headerBytes)
                    if (r is HeaderResult.Ok) {
                        val payload = ByteArray(r.header.payloadLength)
                        if (payload.isNotEmpty()) {
                            readFully(inStream, payload)
                        }
                        when (r.header.type) {
                            MessageType.STATUS -> {
                                Log.i(TAG, "Receiver status received")
                            }
                            MessageType.DISCONNECT -> {
                                Log.i(TAG, "Receiver sent disconnect")
                                closeSocket()
                                break
                            }
                            MessageType.ERROR -> {
                                Log.w(TAG, "Receiver sent error")
                            }
                            else -> {}
                        }
                    }
                }
            } catch (ignored: Exception) {
            }
        }, "CastSprint-TcpReader").apply {
            start()
        }
    }

    private fun readFully(inStream: InputStream, b: ByteArray) {
        var offset = 0
        while (offset < b.size) {
            val count = inStream.read(b, offset, b.size - offset)
            if (count < 0) throw IllegalStateException("EOF reached before reading ${b.size} bytes")
            offset += count
        }
    }

    private fun sleepBeforeRetry() {
        try {
            Thread.sleep(1000)
        } catch (ignored: InterruptedException) {}
    }

    private fun closeSocket() {
        try {
            socket?.close()
        } catch (ignored: Exception) {}
        socket = null
        outStream = null
    }

    override fun stop() {
        if (!isRunning.compareAndSet(true, false)) return
        closeSocket()
        workerThread?.interrupt()
        readerThread?.interrupt()
        workerThread = null
        readerThread = null
    }
}
