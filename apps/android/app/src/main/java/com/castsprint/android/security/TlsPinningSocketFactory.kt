package com.castsprint.android.security

import android.util.Log
import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/**
 * Creates TLS sockets with strict SHA-256 certificate fingerprint pinning.
 *
 * Security guarantees:
 * - End-to-end authenticated encryption in transit over local Wi-Fi.
 * - Strict certificate pinning against the desktop's SHA-256 certificate fingerprint.
 * - No dependency on public Certificate Authorities or Internet connection.
 * - ZERO trust-all fallbacks: any certificate mismatch immediately throws CertificateException.
 */
object TlsPinningSocketFactory {
    private const val TAG = "TlsPinning"

    fun createPinnedSocket(
        host: String,
        port: Int,
        expectedFingerprintSha256: String,
        connectTimeoutMs: Int = 3000,
    ): Socket {
        val cleanExpected = normalizeFingerprint(expectedFingerprintSha256)
        require(cleanExpected.isNotEmpty()) { "Expected certificate fingerprint cannot be empty" }

        val trustManager = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                // Client trust not evaluated here
            }

            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                if (chain.isNullOrEmpty()) {
                    throw CertificateException("Server certificate chain is empty")
                }
                val serverCert = chain[0]
                val digest = MessageDigest.getInstance("SHA-256").digest(serverCert.encoded)
                val actualFingerprint = digest.joinToString("") { "%02X".format(it) }

                if (!actualFingerprint.equals(cleanExpected, ignoreCase = true)) {
                    Log.e(TAG, "Fingerprint mismatch! Expected: $cleanExpected, Got: $actualFingerprint")
                    throw CertificateException(
                        "Untrusted certificate: SHA-256 fingerprint mismatch. " +
                            "Expected: $cleanExpected, got: $actualFingerprint"
                    )
                }
                Log.i(TAG, "Server certificate successfully validated against pinned SHA-256 fingerprint")
            }

            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        }

        val sslContext = SSLContext.getInstance("TLS").apply {
            init(null, arrayOf<TrustManager>(trustManager), SecureRandom())
        }

        val baseSocket = Socket().apply {
            tcpNoDelay = true
            sendBufferSize = 512 * 1024
            connect(InetSocketAddress(host, port), connectTimeoutMs)
        }

        val sslSocket = sslContext.socketFactory.createSocket(
            baseSocket,
            host,
            port,
            true // autoClose baseSocket
        ) as SSLSocket

        sslSocket.useClientMode = true
        sslSocket.startHandshake()
        return sslSocket
    }

    fun normalizeFingerprint(fp: String): String {
        return fp.replace(":", "").replace("-", "").replace(" ", "").trim().uppercase()
    }
}
