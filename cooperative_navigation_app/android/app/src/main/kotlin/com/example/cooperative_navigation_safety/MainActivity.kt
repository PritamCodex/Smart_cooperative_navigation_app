package com.example.cooperative_navigation_safety

import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.pm.PackageManager
import android.provider.Settings
import androidx.annotation.NonNull

class MainActivity: FlutterActivity() {
    
    companion object {
        private const val PERMISSION_REQUEST_CODE = 1001
        private const val LOCATION_SETTINGS_REQUEST = 1002
    }
    
    private lateinit var methodChannel: MethodChannel

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cooperative_navigation_safety/main")
        
        // Register Sensor Service Channel
        val sensorChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sensor_service")
        sensorChannel.setMethodCallHandler(SensorMethodHandler(this))
        
        // Register Nearby Connections Channel
        val nearbyChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nearby_connections")
        nearbyChannel.setMethodCallHandler(ConnectivityMethodHandler(this, nearbyChannel))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermissions" -> {
                    checkPermissions(result)
                }
                "requestPermissions" -> {
                    requestPermissions(result)
                }
                "startForegroundService" -> {
                    startForegroundService(result)
                }
                "stopForegroundService" -> {
                    stopForegroundService(result)
                }
                "checkLocationSettings" -> {
                    checkLocationSettings(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun checkPermissions(result: MethodChannel.Result) {
        val permissions = arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.POST_NOTIFICATIONS
        )

        val grantedPermissions = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }

        val permissionStatus = mapOf(
            "allGranted" to (grantedPermissions.size == permissions.size),
            "grantedCount" to grantedPermissions.size,
            "totalCount" to permissions.size,
            "missingPermissions" to permissions.filter {
                ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
            }
        )

        result.success(permissionStatus)
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        val permissions = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.POST_NOTIFICATIONS
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions.add(Manifest.permission.BLUETOOTH_SCAN)
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT)
            permissions.add(Manifest.permission.BLUETOOTH_ADVERTISE)
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.NEARBY_WIFI_DEVICES)
        }
        
        ActivityCompat.requestPermissions(this, permissions.toTypedArray(), PERMISSION_REQUEST_CODE)
        result.success(true)
    }

    private fun startForegroundService(result: MethodChannel.Result) {
        try {
            ForegroundService.startService(this, "Cooperative Navigation Safety Service")
            result.success(true)
        } catch (e: Exception) {
            result.error("SERVICE_ERROR", "Failed to start foreground service: ${e.message}", null)
        }
    }

    private fun stopForegroundService(result: MethodChannel.Result) {
        try {
            ForegroundService.stopService(this)
            result.success(true)
        } catch (e: Exception) {
            result.error("SERVICE_ERROR", "Failed to stop foreground service: ${e.message}", null)
        }
    }

    private fun checkLocationSettings(result: MethodChannel.Result) {
        val locationManager = getSystemService(LOCATION_SERVICE) as android.location.LocationManager
        val isGpsEnabled = locationManager.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER)
        val isNetworkEnabled = locationManager.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER)
        
        result.success(mapOf(
            "gpsEnabled" to isGpsEnabled,
            "networkEnabled" to isNetworkEnabled,
            "locationEnabled" to (isGpsEnabled || isNetworkEnabled)
        ))
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            methodChannel.invokeMethod("onPermissionsResult", mapOf(
                "granted" to allGranted,
                "results" to grantResults.toList()
            ))
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (requestCode == LOCATION_SETTINGS_REQUEST) {
            checkLocationSettings(object : MethodChannel.Result {
                override fun success(result: Any?) {
                    methodChannel.invokeMethod("onLocationSettingsResult", result)
                }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
                override fun notImplemented() {}
            })
        }
    }
}