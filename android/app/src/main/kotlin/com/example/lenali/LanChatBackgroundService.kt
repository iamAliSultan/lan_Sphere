package com.example.lenali

import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat

class LanChatBackgroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(
            888,
            NotificationCompat.Builder(this, BuildConfig.NOTIFICATION_CHANNEL_ID)
                .setContentTitle("LAN Chat Running")
                .setContentText("Listening for messages")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }
}