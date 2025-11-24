package com.example.cooperative_navigation_safety

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import android.location.GnssStatus
import android.os.Build
import androidx.annotation.RequiresApi

class CooperativeNavigationSafetyPlugin: FlutterPlugin, MethodCallHandler, SensorEventListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var sensorManager: SensorManager
    private lateinit var locationManager: LocationManager
    
    private var accelerometer: Sensor? = null
    private var gyroscope: Sensor? = null
    private var magnetometer: Sensor? = null
    private var gravitySensor: Sensor? = null
    
    private val sensorData = mutableMapOf<String, FloatArray>()
    private val mainHandler = Handler(Looper.getMainLooper())
    
    private var gnssStatusCallback: GnssStatus.Callback? = null
    private var locationListener: LocationListener? = null

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "cooperative_navigation_safety/sensors")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
        
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        
        initializeSensors()
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getGnssRawData" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    getGnssRawData(result)
                } else {
                    result.error("UNSUPPORTED", "GNSS raw data requires Android 7.0+", null)
                }
            }
            "getHeading" -> {
                getHeading(result)
            }
            "startLocationUpdates" -> {
                startLocationUpdates(result)
            }
            "stopLocationUpdates" -> {
                stopLocationUpdates(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        stopSensors()
    }

    private fun initializeSensors() {
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        gyroscope = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        magnetometer = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
        gravitySensor = sensorManager.getDefaultSensor(Sensor.TYPE_GRAVITY)
        
        startSensors()
    }

    private fun startSensors() {
        val sensorDelay = SensorManager.SENSOR_DELAY_FASTEST
        
        accelerometer?.let {
            sensorManager.registerListener(this, it, sensorDelay)
        }
        
        gyroscope?.let {
            sensorManager.registerListener(this, it, sensorDelay)
        }
        
        magnetometer?.let {
            sensorManager.registerListener(this, it, sensorDelay)
        }
        
        gravitySensor?.let {
            sensorManager.registerListener(this, it, sensorDelay)
        }
    }

    private fun stopSensors() {
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                sensorData["accelerometer"] = event.values.clone()
            }
            Sensor.TYPE_GYROSCOPE -> {
                sensorData["gyroscope"] = event.values.clone()
            }
            Sensor.TYPE_MAGNETIC_FIELD -> {
                sensorData["magnetometer"] = event.values.clone()
            }
            Sensor.TYPE_GRAVITY -> {
                sensorData["gravity"] = event.values.clone()
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Handle accuracy changes if needed
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun getGnssRawData(result: Result) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) 
            != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
            return
        }

        try {
            gnssStatusCallback = object : GnssStatus.Callback() {
                override fun onSatelliteStatusChanged(status: GnssStatus) {
                    val satelliteData = mutableMapOf<String, Any>()
                    
                    for (i in 0 until status.satelliteCount) {
                        satelliteData["satellite_$i"] = mapOf(
                            "constellationType" to status.getConstellationType(i),
                            "svid" to status.getSvid(i),
                            "carrierFrequencyHz" to status.getCarrierFrequencyHz(i),
                            "cn0DbHz" to status.getCn0DbHz(i),
                            "elevationDegrees" to status.getElevationDegrees(i),
                            "azimuthDegrees" to status.getAzimuthDegrees(i),
                            "hasAlmanacData" to status.hasAlmanacData(i),
                            "hasEphemerisData" to status.hasEphemerisData(i),
                            "usedInFix" to status.usedInFix(i)
                        )
                    }
                    
                    result.success(satelliteData)
                }
            }
            
            locationManager.registerGnssStatusCallback(gnssStatusCallback!!, mainHandler)
            
        } catch (e: Exception) {
            result.error("GNSS_ERROR", "Failed to get GNSS data: ${e.message}", null)
        }
    }

    private fun getHeading(result: Result) {
        val accelerometerData = sensorData["accelerometer"]
        val magnetometerData = sensorData["magnetometer"]
        
        if (accelerometerData != null && magnetometerData != null) {
            val rotationMatrix = FloatArray(9)
            val inclinationMatrix = FloatArray(9)
            val orientation = FloatArray(3)
            
            if (SensorManager.getRotationMatrix(
                    rotationMatrix, inclinationMatrix,
                    accelerometerData, magnetometerData
                )) {
                SensorManager.getOrientation(rotationMatrix, orientation)
                val heading = Math.toDegrees(orientation[0].toDouble())
                result.success((heading + 360) % 360)
            } else {
                result.error("SENSOR_ERROR", "Failed to get rotation matrix", null)
            }
        } else {
            result.error("SENSOR_UNAVAILABLE", "Required sensors not available", null)
        }
    }

    private fun startLocationUpdates(result: Result) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) 
            != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
            return
        }

        try {
            locationListener = object : LocationListener {
                override fun onLocationChanged(location: Location) {
                    // Handle location updates
                }
                
                override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {
                    // Handle status changes for older Android versions
                }
                
                override fun onProviderEnabled(provider: String) {
                    // Handle provider enabled
                }
                
                override fun onProviderDisabled(provider: String) {
                    // Handle provider disabled
                }
            }
            
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                1000, // 1 second
                0f,   // No minimum distance
                locationListener!!
            )
            
            result.success(true)
        } catch (e: Exception) {
            result.error("LOCATION_ERROR", "Failed to start location updates: ${e.message}", null)
        }
    }

    private fun stopLocationUpdates(result: Result) {
        locationListener?.let {
            locationManager.removeUpdates(it)
            locationListener = null
        }
        result.success(true)
    }
}