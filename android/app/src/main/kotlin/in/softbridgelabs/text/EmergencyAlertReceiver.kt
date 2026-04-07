package `in`.softbridgelabs.text

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * Receives BROADCAST_WAP_PUSH for Wireless Emergency Alerts (WEA/CMAS/CBE).
 * Also handles standard cell broadcast messages (AMBER Alerts, Presidential Alerts, etc.)
 */
class EmergencyAlertReceiver : BroadcastReceiver() {

    companion object {
        private const val EA_CHANNEL_ID = "emergency_alert_channel"
        private const val EA_CHANNEL_NAME = "Emergency Alerts"

        // Standard cell-broadcast channel ranges (CMAS)
        private val PRESIDENTIAL_RANGE   = 4370..4370
        private val EXTREME_RANGE        = 4371..4372
        private val SEVERE_RANGE         = 4373..4379
        private val AMBER_RANGE          = 4380..4380
        private val PUBLIC_SAFETY_RANGE  = 4381..4393
        private val EXERCISE_RANGE       = 4352..4354

        fun categorize(serviceCategory: Int): Pair<String, Int> {
            return when (serviceCategory) {
                in PRESIDENTIAL_RANGE  -> Pair("Presidential Alert 🚨", android.R.drawable.ic_dialog_alert)
                in EXTREME_RANGE       -> Pair("Extreme Threat ⚠️",      android.R.drawable.ic_dialog_alert)
                in SEVERE_RANGE        -> Pair("Severe Threat 🔔",        android.R.drawable.ic_dialog_info)
                in AMBER_RANGE         -> Pair("AMBER Alert 🟡",          android.R.drawable.ic_dialog_info)
                in PUBLIC_SAFETY_RANGE -> Pair("Public Safety Message",   android.R.drawable.ic_dialog_info)
                in EXERCISE_RANGE      -> Pair("Emergency Exercise",      android.R.drawable.ic_dialog_info)
                else                   -> Pair("Emergency Alert",          android.R.drawable.ic_dialog_alert)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        // Check user opt-in
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("flutter.emergency_alerts_enabled", true)) return

        val body = extractMessage(intent) ?: return
        val serviceCategory = intent.getIntExtra("serviceCategory", -1)
        val (title, icon) = categorize(serviceCategory)

        showEmergencyNotification(context, title, body, icon)
    }

    private fun extractMessage(intent: Intent): String? {
        // Standard GSM CBS message format (Android 4.4+)
        val pdus = intent.getSerializableExtra("pdus") as? Array<*> ?: return null
        val sb = StringBuilder()
        for (pdu in pdus) {
            if (pdu is ByteArray) {
                // Simple UTF-8 decode attempt (actual CBS parsing differs per codec)
                try {
                    sb.append(String(pdu, Charsets.UTF_8).trimEnd('\u0000'))
                } catch (_: Exception) {
                    try { sb.append(String(pdu, Charsets.ISO_8859_1).trimEnd('\u0000')) } catch (_: Exception) {}
                }
            }
        }
        // Fallback: some intents carry a plaintext "message" extra
        return if (sb.isNotBlank()) sb.toString().trim()
               else intent.getStringExtra("message")?.trim()
    }

    private fun showEmergencyNotification(
        context: Context, title: String, body: String, iconRes: Int
    ) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createChannel(nm)

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("show_emergency_alert", true)
            putExtra("alert_title", title)
            putExtra("alert_body", body)
        }
        val pi = PendingIntent.getActivity(
            context, System.currentTimeMillis().toInt(), openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, EA_CHANNEL_ID)
            .setSmallIcon(iconRes)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setDefaults(Notification.DEFAULT_ALL)
            .setFullScreenIntent(pi, true)  // appear as heads-up on lock screen
            .setContentIntent(pi)
            .build()

        nm.notify(("ea_$title").hashCode(), notification)
    }

    private fun createChannel(nm: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                EA_CHANNEL_ID, EA_CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Government emergency and broadcast alerts"
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(ch)
        }
    }
}
