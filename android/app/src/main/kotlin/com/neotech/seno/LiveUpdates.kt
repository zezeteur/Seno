package com.neotech.seno

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Live Updates (Android 16+) : notification promue (chip barre d'état,
 * écran verrouillé) basée sur Notification.ProgressStyle.
 * Avant Android 16 : notification ongoing classique avec barre de progression.
 */
class LiveUpdates(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "seno/live_updates"
        private const val NOTIF_CHANNEL_ID = "seno_live_updates"
        private const val PERMISSION_REQUEST_CODE = 4201
    }

    private val manager =
        activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
        ensureChannel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermission" -> {
                requestPermission()
                result.success(null)
            }
            "isSupported" -> result.success(
                Build.VERSION.SDK_INT >= 36 && manager.canPostPromotedNotifications()
            )
            "show" -> {
                if (!hasPermission()) return result.success(false)
                manager.notify(call.argument<Int>("id") ?: 0, build(call))
                result.success(true)
            }
            "end" -> {
                manager.cancel(call.argument<Int>("id") ?: 0)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun hasPermission(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPermission() {
        if (Build.VERSION.SDK_INT >= 33 && !hasPermission()) {
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST_CODE
            )
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        // Importance >= DEFAULT requise pour la promotion.
        val channel = NotificationChannel(
            NOTIF_CHANNEL_ID, "Suivi des transactions", NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Progression en direct des paiements et retraits"
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun build(call: MethodCall): Notification {
        val title = call.argument<String>("title") ?: "Seno"
        val text = call.argument<String>("text")
        val shortText = call.argument<String>("shortText")
        val progress = (call.argument<Int>("progress") ?: 0).coerceIn(0, 100)
        val indeterminate = call.argument<Boolean>("indeterminate") ?: false
        val finished = call.argument<Boolean>("finished") ?: false
        val steps = call.argument<Int>("steps") ?: 0

        val launch = activity.packageManager.getLaunchIntentForPackage(activity.packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP }
        val contentIntent = PendingIntent.getActivity(
            activity, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = (if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(activity, NOTIF_CHANNEL_ID)
        else
            @Suppress("DEPRECATION") Notification.Builder(activity))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(contentIntent)
            .setOnlyAlertOnce(true)
            .setOngoing(!finished)
            .setAutoCancel(finished)

        if (Build.VERSION.SDK_INT >= 36) {
            val style = Notification.ProgressStyle()
                .setProgressIndeterminate(indeterminate)
                .setProgress(progress)
            if (steps > 1) {
                // Segments égaux + un point à chaque étape.
                val segLen = 100 / steps
                style.setProgressSegments(
                    List(steps) { Notification.ProgressStyle.Segment(segLen) }
                )
                style.setProgressPoints(
                    (1 until steps).map { Notification.ProgressStyle.Point(it * segLen) }
                )
            } else {
                style.setProgressSegments(listOf(Notification.ProgressStyle.Segment(100)))
            }
            builder.setStyle(style)
            if (!finished) builder.addExtras(android.os.Bundle().apply {
                putBoolean("android.requestPromotedOngoing", true)
            })
            shortText?.let { builder.setShortCriticalText(it) }
        } else if (!finished) {
            builder.setProgress(100, progress, indeterminate)
        }
        return builder.build()
    }
}
