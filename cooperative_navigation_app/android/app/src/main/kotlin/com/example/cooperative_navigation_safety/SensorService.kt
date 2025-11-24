package com.example.cooperative_navigation_safety

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

data class SensorData(
    val timestamp: Long,
    val latitude: Double,
    val longitude: Double,
    val altitude: Double,
    val speed: Float,
    val heading: Float,
    val accuracy: Float,
    val accX: Float, val accY: Float, val accZ: Float,
    val gyroX: Float, val gyroY: Float, val gyroZ: Float,
    val rssi: Int,
    val batteryLevel: Int,
    val thermalState: Int
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "timestamp" to timestamp,
            "latitude" to latitude,
            "longitude" to longitude,
            "altitude" to altitude,
            "speed" to speed,
            "heading" to heading,
            "accuracy" to accuracy,
            "accX" to accX, "accY" to accY, "accZ" to accZ,
            "gyroX" to gyroX, "gyroY" to gyroY, "gyroZ" to gyroZ,
            "rssi" to rssi,
            "batteryLevel" to batteryLevel,
            "thermalState" to thermalState
        )
    }
}

class SensorService(private val context: Context) : SensorEventListener, LocationListener {
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val wifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager

    private var latestAccel = FloatArray(3)
    private var latestGyro = FloatArray(3)
    private var latestLocation: Location? = null

    private var isRunning = false

    fun start(updateRateHz: Int) {
        if (isRunning) return
        isRunning = true

        // Register Sensors
        sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.also { accelerometer ->
            sensorManager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_GAME)
        }
        sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)?.also { gyroscope ->
            sensorManager.registerListener(this, gyroscope, SensorManager.SENSOR_DELAY_GAME)
        }

        // Register Location
        try {
            val minTimeMs = (1000 / updateRateHz).toLong()
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                minTimeMs,
                0f,
                this
            )
        } catch (e: SecurityException) {
            // Permission must be checked before calling start()
            e.printStackTrace()
        }
    }

    fun stop() {
        if (!isRunning) return
        isRunning = false
        sensorManager.unregisterListener(this)
        locationManager.removeUpdates(this)
    }

    fun getCurrentSensorData(): SensorData {
        return SensorData(
            timestamp = System.currentTimeMillis(),
            latitude = latestLocation?.latitude ?: 0.0,
            longitude = latestLocation?.longitude ?: 0.0,
            altitude = latestLocation?.altitude ?: 0.0,
            speed = latestLocation?.speed ?: 0f,
            heading = latestLocation?.bearing ?: 0f,
            accuracy = latestLocation?.accuracy ?: 999f,
            accX = latestAccel[0], accY = latestAccel[1], accZ = latestAccel[2],
            gyroX = latestGyro[0], gyroY = latestGyro[1], gyroZ = latestGyro[2],
            rssi = getRSSI(),
            batteryLevel = getBatteryLevel(),
            thermalState = getThermalState()
        )
    }

    private fun getRSSI(): Int {
        return try {
            val wifiInfo = wifiManager.connectionInfo
            wifiInfo.rssi
        } catch (e: Exception) {
            0
        }
    }

    private fun getBatteryLevel(): Int {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
        return bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
    }

    private fun getThermalState(): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            return powerManager.currentThermalStatus
        }
        return -1 // Not supported
    }

    // SensorEventListener
    override fun onSensorChanged(event: SensorEvent?) {
        event?.let {
            when (it.sensor.type) {
                Sensor.TYPE_ACCELEROMETER -> {
                    System.arraycopy(it.values, 0, latestAccel, 0, 3)
                }
                Sensor.TYPE_GYROSCOPE -> {
                    System.arraycopy(it.values, 0, latestGyro, 0, 3)
                }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // LocationListener
    override fun onLocationChanged(location: Location) {
        latestLocation = location
    }

    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    override fun onProviderEnabled(provider: String) {}
    override fun onProviderDisabled(provider: String) {}
}

class SensorMethodHandler(private val context: Context) : MethodChannel.MethodCallHandler {
    private val service = SensorService(context)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startSensors" -> {
                val rate = call.argument<Int>("rate") ?: 10
                service.start(rate)
                result.success(null)
            }
            "stopSensors" -> {
                service.stop()
                result.success(null)
            }
            "getSensorData" -> {
                val data = service.getCurrentSensorData()
                result.success(data.toMap())
            }
            else -> result.notImplemented()
        }
    }
}
