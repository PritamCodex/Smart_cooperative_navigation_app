package com.example.cooperative_navigation_safety

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.AlarmManager
import android.content.Intent
import android.content.Context
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class ForegroundService : Service() {
    
    companion object {
        const val CHANNEL_ID = "CooperativeNavigationSafety"
        const val CHANNEL_NAME = "Navigation Safety Service"
        const val NOTIFICATION_ID = 1
        const val ACTION_STOP = "STOP_SERVICE"
        
        fun startService(context: Context, message: String) {
            val serviceIntent = Intent(context, ForegroundService::class.java)
            serviceIntent.putExtra("inputExtra", message)
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        }
        
        fun stopService(context: Context) {
            val serviceIntent = Intent(context, ForegroundService::class.java)
            context.stopService(serviceIntent)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }
        
        createNotificationChannel()
        
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
        
        // Start the main service logic here
        startServiceLogic()
        
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        stopServiceLogic()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Cooperative Navigation Safety Service"
                enableLights(false)
                enableVibration(false)
                setShowBadge(false)
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun createNotification(): Notification {
        val stopIntent = Intent(this, ForegroundService::class.java)
        stopIntent.action = ACTION_STOP
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Cooperative Navigation Safety")
            .setContentText("Active - Monitoring nearby devices")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopPendingIntent
            )
            .build()
    }

    private fun startServiceLogic() {
        // Initialize sensor services
        // Start location updates
        // Start Nearby Connections
        // Start collision detection
        
        // Schedule periodic tasks if needed
        schedulePeriodicTasks()
    }

    private fun stopServiceLogic() {
        // Clean up resources
        // Stop location updates
        // Stop Nearby Connections
        // Stop sensors
    }

    private fun schedulePeriodicTasks() {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, ForegroundService::class.java)
        val pendingIntent = PendingIntent.getService(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val interval = 60 * 1000L // 1 minute
        alarmManager.setRepeating(
            AlarmManager.RTC_WAKEUP,
            SystemClock.elapsedRealtime() + interval,
            interval,
            pendingIntent
        )
    }
}