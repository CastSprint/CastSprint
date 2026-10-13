package com.castsprint.android.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.util.Log
import java.util.concurrent.ConcurrentHashMap

data class DiscoveredDevice(
    val name: String,
    val host: String,
    val port: Int,
    val fingerprint: String? = null,
)

/**
 * Discovers CastSprint desktop receivers on the local Wi-Fi network using mDNS (DNS-SD).
 * Service type: _castsprint._tcp
 */
class LanDiscovery(context: Context) {
    companion object {
        private const val TAG = "LanDiscovery"
        const val SERVICE_TYPE = "_castsprint._tcp."
    }

    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
    private val devices = ConcurrentHashMap<String, DiscoveredDevice>()

    var onDeviceFound: ((DiscoveredDevice) -> Unit)? = null
    var onDeviceLost: ((String) -> Unit)? = null
    var onError: ((String) -> Unit)? = null

    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var isDiscovering = false

    fun startDiscovery() {
        if (nsdManager == null) {
            onError?.invoke("mDNS (NsdManager) not available on this device")
            return
        }
        if (isDiscovering) return

        val listener = object : NsdManager.DiscoveryListener {
            override fun onStartDiscoveryFailed(serviceType: String?, errorCode: Int) {
                Log.e(TAG, "Discovery start failed: error code $errorCode")
                isDiscovering = false
                onError?.invoke("Discovery failed: error $errorCode")
            }

            override fun onStopDiscoveryFailed(serviceType: String?, errorCode: Int) {
                Log.e(TAG, "Discovery stop failed: error code $errorCode")
                isDiscovering = false
            }

            override fun onDiscoveryStarted(serviceType: String?) {
                Log.i(TAG, "mDNS discovery started for $serviceType")
                isDiscovering = true
            }

            override fun onDiscoveryStopped(serviceType: String?) {
                Log.i(TAG, "mDNS discovery stopped")
                isDiscovering = false
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo?) {
                if (serviceInfo == null) return
                Log.i(TAG, "Service found: ${serviceInfo.serviceName}")
                resolveService(serviceInfo)
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo?) {
                val name = serviceInfo?.serviceName ?: return
                Log.i(TAG, "Service lost: $name")
                devices.remove(name)
                onDeviceLost?.invoke(name)
            }
        }

        try {
            nsdManager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
            discoveryListener = listener
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to start mDNS discovery", t)
            onError?.invoke("Failed to start mDNS: ${t.message}")
        }
    }

    @Suppress("DEPRECATION")
    private fun resolveService(serviceInfo: NsdServiceInfo) {
        val nsd = nsdManager ?: return
        val resolveListener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo?, errorCode: Int) {
                Log.w(TAG, "Failed to resolve service ${info?.serviceName}: error $errorCode")
            }

            override fun onServiceResolved(info: NsdServiceInfo?) {
                if (info == null) return
                val host = info.host?.hostAddress ?: return
                val port = info.port
                val name = info.serviceName ?: "CastSprint Receiver"

                var fp: String? = null
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    val attributes = info.attributes
                    fp = attributes["fp"]?.let { String(it) }
                }

                val device = DiscoveredDevice(name, host, port, fp)
                devices[name] = device
                Log.i(TAG, "Resolved device: $name at $host:$port (fp=$fp)")
                onDeviceFound?.invoke(device)
            }
        }

        try {
            nsd.resolveService(serviceInfo, resolveListener)
        } catch (t: Throwable) {
            Log.w(TAG, "Exception during service resolution", t)
        }
    }

    fun stopDiscovery() {
        if (!isDiscovering) return
        discoveryListener?.let {
            try {
                nsdManager?.stopServiceDiscovery(it)
            } catch (ignored: Throwable) {}
        }
        discoveryListener = null
        isDiscovering = false
        devices.clear()
    }
}
