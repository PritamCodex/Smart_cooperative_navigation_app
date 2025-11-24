# Kotlin (Android) Code Templates

These templates are for `android/app/src/main/kotlin/.../MainActivity.kt` and `AndroidManifest.xml` to ensure stability on older devices.

## 1. BLE Stability Tweaks (MainActivity.kt)

Add this to your `MainActivity` to optimize Bluetooth settings for Nearby Connections.

```kotlin
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.ScanSettings

private fun optimizeBluetooth() {
    val adapter = BluetoothAdapter.getDefaultAdapter()
    if (adapter != null && adapter.isEnabled) {
        // Force Low Latency mode if possible (Android 8+)
        // Note: Nearby Connections handles this internally, but we can request priority
    }
}
```

**Better Approach**: Use `ConnectionOptions` in Flutter side, but ensure Android Manifest has:

```xml
<!-- AndroidManifest.xml -->
<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
<uses-permission android:name="android.permission.REQUEST_COMPANION_RUN_IN_BACKGROUND" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```

## 2. Power Management (Battery Optimization)

To prevent the OS from killing the app on Weak Nodes:

```kotlin
import android.content.Intent
import android.provider.Settings
import android.net.Uri
import android.os.PowerManager
import android.content.Context

private fun requestIgnoreBatteryOptimizations() {
    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
    val packageName = packageName
    
    if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
        val intent = Intent()
        intent.action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
        intent.data = Uri.parse("package:$packageName")
        startActivity(intent)
    }
}
```

## 3. Foreground Service Tweaks (ForegroundService.kt)

Ensure the service type is correct for Android 14+.

```kotlin
// In ForegroundService.kt
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
    startForeground(
        NOTIFICATION_ID, 
        notification, 
        ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
    )
} else {
    startForeground(NOTIFICATION_ID, notification)
}
```

## 4. Nearby Packet Structs (Data Class)

If you were implementing native handling (optional, since we use Flutter channel):

```kotlin
data class SensorPacket(
    val deviceId: String,
    val lat: Double,
    val lon: Double,
    val acc: Float,
    val timestamp: Long
) {
    fun toByteArray(): ByteArray {
        // Custom serialization for speed
        val buffer = ByteBuffer.allocate(32)
        buffer.putDouble(lat)
        buffer.putDouble(lon)
        buffer.putFloat(acc)
        buffer.putLong(timestamp)
        return buffer.array()
    }
}
```
