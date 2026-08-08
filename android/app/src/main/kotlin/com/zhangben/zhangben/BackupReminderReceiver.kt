package com.zhangben.zhangben

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.util.Calendar

internal object BackupReminderScheduler {
    const val DEFAULT_DAY_OF_WEEK = 7 // Dart DateTime.weekday: Sunday.
    const val DEFAULT_HOUR = 20
    const val DEFAULT_MINUTE = 0

    private const val PREFERENCES = "backup_reminder"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_DAY_OF_WEEK = "day_of_week"
    private const val KEY_HOUR = "hour"
    private const val KEY_MINUTE = "minute"
    private const val ALARM_REQUEST_CODE = 6101
    private const val WEEK_MILLIS = 7L * AlarmManager.INTERVAL_DAY

    fun schedule(context: Context, dayOfWeek: Int, hour: Int, minute: Int) {
        require(dayOfWeek in 1..7) { "提醒星期必须是 1（周一）到 7（周日）" }
        require(hour in 0..23) { "提醒小时必须是 0 到 23" }
        require(minute in 0..59) { "提醒分钟必须是 0 到 59" }

        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENABLED, true)
            .putInt(KEY_DAY_OF_WEEK, dayOfWeek)
            .putInt(KEY_HOUR, hour)
            .putInt(KEY_MINUTE, minute)
            .apply()

        createNotificationChannel(context)
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            nextTriggerAtMillis(dayOfWeek, hour, minute),
            WEEK_MILLIS,
            alarmIntent(context),
        )
    }

    fun rescheduleIfEnabled(context: Context) {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        if (!preferences.getBoolean(KEY_ENABLED, false)) return
        schedule(
            context,
            preferences.getInt(KEY_DAY_OF_WEEK, DEFAULT_DAY_OF_WEEK),
            preferences.getInt(KEY_HOUR, DEFAULT_HOUR),
            preferences.getInt(KEY_MINUTE, DEFAULT_MINUTE),
        )
    }

    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(alarmIntent(context))
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENABLED, false)
            .apply()
    }

    fun createNotificationChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                BackupReminderReceiver.CHANNEL_ID,
                "每周备份提醒",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "提醒把账目备份发给家人保管"
            },
        )
    }

    private fun alarmIntent(context: Context): PendingIntent {
        val intent = Intent(context, BackupReminderReceiver::class.java).apply {
            action = BackupReminderReceiver.ACTION_REMIND_BACKUP
        }
        return PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun nextTriggerAtMillis(dayOfWeek: Int, hour: Int, minute: Int): Long {
        val now = Calendar.getInstance()
        val next = Calendar.getInstance().apply {
            set(Calendar.DAY_OF_WEEK, dartWeekdayToCalendar(dayOfWeek))
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= now.timeInMillis) add(Calendar.DAY_OF_YEAR, 7)
        }
        return next.timeInMillis
    }

    private fun dartWeekdayToCalendar(dayOfWeek: Int): Int {
        return if (dayOfWeek == 7) Calendar.SUNDAY else dayOfWeek + 1
    }
}

class BackupReminderReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_REMIND_BACKUP = "com.zhangben.zhangben.REMIND_BACKUP"
        const val CHANNEL_ID = "weekly_backup_reminder"
        private const val NOTIFICATION_ID = 6201
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            BackupReminderScheduler.rescheduleIfEnabled(context)
            return
        }
        if (intent.action != ACTION_REMIND_BACKUP) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        BackupReminderScheduler.createNotificationChannel(context)
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                context,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_backup)
            .setContentTitle("该备份账本了")
            .setContentText("把最新账目备份发给家人，换手机时更安心。")
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, notification)
    }
}
