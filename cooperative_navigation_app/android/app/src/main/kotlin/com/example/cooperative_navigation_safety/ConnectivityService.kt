package com.example.cooperative_navigation_safety

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ConnectivityService(private val context: Context, private val channel: MethodChannel) {

    private val connectionsClient = Nearby.getConnectionsClient(context)
    private val serviceId = "com.example.cooperative_navigation_safety"
    private val strategy = Strategy.P2P_CLUSTER

    private val connectedEndpoints = mutableMapOf<String, String>() // ID -> Name
    
    // BLE/Wi-Fi Stability: High-performance Wi-Fi lock
    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    fun startAdvertising(deviceName: String) {
        val options = AdvertisingOptions.Builder().setStrategy(strategy).build()
        connectionsClient.startAdvertising(
            deviceName,
            serviceId,
            connectionLifecycleCallback,
            options
        )
        .addOnSuccessListener { Log.d(TAG, "Advertising started") }
        .addOnFailureListener { e -> Log.e(TAG, "Advertising failed", e) }
    }

    fun startDiscovery() {
        val options = DiscoveryOptions.Builder().setStrategy(strategy).build()
        connectionsClient.startDiscovery(
            serviceId,
            endpointDiscoveryCallback,
            options
        )
        .addOnSuccessListener { Log.d(TAG, "Discovery started") }
        .addOnFailureListener { e -> Log.e(TAG, "Discovery failed", e) }
    }

    fun stopAll() {
        connectionsClient.stopAdvertising()
        connectionsClient.stopDiscovery()
        connectionsClient.stopAllEndpoints()
        connectedEndpoints.clear()
        releaseWakeLocks()
        Log.d(TAG, "Stopped all nearby operations")
    }

    fun sendPayload(endpointId: String, bytes: ByteArray) {
        val payload = Payload.fromBytes(bytes)
        connectionsClient.sendPayload(endpointId, payload)
            .addOnFailureListener { e -> Log.e(TAG, "Send failed", e) }
    }
    
    /// ========================================================================
    /// BLE/Wi-Fi STABILITY ENHANCEMENTS
    /// ========================================================================
    
    /** Acquires high-performance Wi-Fi lock to prevent Wi-Fi sleep during NC. */
    fun acquireWifiLock() {
        if (wifiLock == null) {
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wifiLock = wifiManager.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "NearbyConnectionsLock"
            )
            wifiLock?.acquire()
            Log.d(TAG, "Wi-Fi lock acquired (high performance mode)")
        }
    }
    
    /** Acquires partial wake lock to prevent CPU sleep during active connections. */
    fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "NearbyService::WakeLock"
            )
            wakeLock?.acquire(10 * 60 * 1000L) // 10 minutes max
            Log.d(TAG, "Wake lock acquired (partial)")
        }
    }
    
    /** Releases all locks. */
    fun releaseWakeLocks() {
        wifiLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d(TAG, "Wi-Fi lock released")
            }
        }
        wifiLock = null
        
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d(TAG, "Wake lock released")
            }
        }
        wakeLock = null
    }
    
    /** Requests battery optimization exemption (requires user approval). */
    fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val packageName = context.packageName
            
            if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                try {
                    context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    Log.d(TAG, "Battery optimization exemption requested")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to request battery exemption", e)
                }
            } else {
                Log.d(TAG, "Already exempt from battery optimization")
            }
        }
    }
    
    /// ========================================================================
    /// CONNECTION LIFECYCLE CALLBACKS
    /// ========================================================================

    private val connectionLifecycleCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            Log.d(TAG, "Connection initiated: $endpointId")
            // Automatically accept connection
            connectionsClient.acceptConnection(endpointId, payloadCallback)
        }

        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
            if (result.status.isSuccess) {
                Log.d(TAG, "Connected to $endpointId")
                // We don't have the name here easily unless we stored it from onConnectionInitiated
                // For now, we just notify Flutter
                channel.invokeMethod("onConnected", mapOf("endpointId" to endpointId))
            } else {
                Log.e(TAG, "Connection failed: ${result.status.statusCode}")
            }
        }

        override fun onDisconnected(endpointId: String) {
            Log.d(TAG, "Disconnected from $endpointId")
            connectedEndpoints.remove(endpointId)
            channel.invokeMethod("onDisconnected", mapOf("endpointId" to endpointId))
        }
    }

    private val endpointDiscoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            Log.d(TAG, "Endpoint found: $endpointId (${info.endpointName})")
            // Automatically request connection
            connectionsClient.requestConnection(
                "Device_${System.currentTimeMillis()}", // My name (should be consistent)
                endpointId,
                connectionLifecycleCallback
            )
        }

        override fun onEndpointLost(endpointId: String) {
            Log.d(TAG, "Endpoint lost: $endpointId")
        }
    }

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            if (payload.type == Payload.Type.BYTES) {
                val bytes = payload.asBytes()
                if (bytes != null) {
                    channel.invokeMethod("onPayloadReceived", mapOf(
                        "endpointId" to endpointId,
                        "bytes" to bytes
                    ))
                }
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {
            // Optional: Track progress
        }
    }

    companion object {
        private const val TAG = "ConnectivityService"
    }
}

class ConnectivityMethodHandler(private val context: Context, private val channel: MethodChannel) : MethodChannel.MethodCallHandler {
    private val service = ConnectivityService(context, channel)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startAdvertising" -> {
                val deviceName = call.argument<String>("deviceName") ?: "Unknown"
                service.startAdvertising(deviceName)
                // Acquire locks for stability
                service.acquireWifiLock()
                service.acquireWakeLock()
                result.success(null)
            }
            "startDiscovery" -> {
                service.startDiscovery()
                // Acquire locks for stability
                service.acquireWifiLock()
                service.acquireWakeLock()
                result.success(null)
            }
            "stopAll" -> {
                service.stopAll() // This also releases locks
                result.success(null)
            }
            "sendPayload" -> {
                val endpointId = call.argument<String>("endpointId")
                val bytes = call.argument<ByteArray>("bytes")
                if (endpointId != null && bytes != null) {
                    service.sendPayload(endpointId, bytes)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGS", "endpointId or bytes missing", null)
                }
            }
            "requestConnection" -> {
                // Support for reconnection from Dart side
                val endpointId = call.argument<String>("endpointId")
                val endpointName = call.argument<String>("endpointName") ?: "Unknown"
                if (endpointId != null) {
                    // Re-request connection (discovery should find it again)
                    service.startDiscovery()
                    result.success(null)
                } else {
                    result.error("INVALID_ARGS", "endpointId missing", null)
                }
            }
            "requestBatteryExemption" -> {
                service.requestBatteryOptimizationExemption()
                result.success(null)
            }
            "startForegroundService" -> {
                // Start foreground service for background operation
                try {
                    ForegroundService.startService(context, "Cooperative Navigation Active")
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SERVICE_ERROR", "Failed to start foreground service: ${e.message}", null)
                }
            }
            "getDeviceId" -> {
                // Return a unique ID for this device
                val id = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
                result.success(id)
            }
            else -> result.notImplemented()
        }
    }
}
