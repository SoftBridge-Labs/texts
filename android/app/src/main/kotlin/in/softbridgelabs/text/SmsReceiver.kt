package `in`.softbridgelabs.text

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.provider.Telephony
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import java.util.regex.Pattern

class SmsReceiver : BroadcastReceiver() {

    companion object {
        private const val CHANNEL_ID = "sms_channel"
        private const val CHANNEL_NAME = "SMS Notifications"
        private const val OTP_CHANNEL_ID = "otp_channel"
        private const val OTP_CHANNEL_NAME = "OTP Notifications"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val PREF_OTP_AUTO_DELETE = "flutter.otp_auto_delete_enabled"
        private const val PREF_OTP_DELETE_MINUTES = "flutter.otp_delete_minutes"
        private const val DEFAULT_DELETE_MINUTES = 10

        // Regex patterns to detect OTP messages
        private val OTP_PATTERNS = listOf(
            Pattern.compile("\\b(\\d{4,8})\\b.*(?:otp|one.?time|passcode|verification|code|pin)", Pattern.CASE_INSENSITIVE),
            Pattern.compile("(?:otp|one.?time|passcode|verification|code|pin).*\\b(\\d{4,8})\\b", Pattern.CASE_INSENSITIVE),
            Pattern.compile("\\b([A-Z0-9]{4,8})\\b.*(?:otp|verification|code)", Pattern.CASE_INSENSITIVE)
        )

        fun extractOtp(body: String): String? {
            for (pattern in OTP_PATTERNS) {
                val matcher = pattern.matcher(body)
                if (matcher.find()) {
                    val group = matcher.group(1)
                    if (group != null && group.length in 4..8) return group
                }
            }
            return null
        }

        fun isOtpMessage(body: String): Boolean = extractOtp(body) != null
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Telephony.Sms.Intents.SMS_DELIVER_ACTION ||
            intent.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION
        ) {
            val isDefaultSmsApp = Telephony.Sms.getDefaultSmsPackage(context) == context.packageName
            if (intent.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION && isDefaultSmsApp) return
            if (intent.action == Telephony.Sms.Intents.SMS_DELIVER_ACTION && !isDefaultSmsApp) return

            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            if (messages.isNullOrEmpty()) return

            val grouped = mutableMapOf<String, StringBuilder>()
            for (msg in messages) {
                val sender = msg.displayOriginatingAddress ?: "Unknown"
                grouped.getOrPut(sender) { StringBuilder() }.append(msg.displayMessageBody ?: "")
            }

            for ((sender, body) in grouped) {
                val bodyStr = body.toString()
                if (isOtpMessage(bodyStr)) {
                    val messageId = if (isDefaultSmsApp && intent.action == Telephony.Sms.Intents.SMS_DELIVER_ACTION) {
                         saveIncomingMessages(context, messages)
                    } else -1L
                    
                    showOtpNotification(context, sender, bodyStr)
                    scheduleOtpDeletion(context, sender, messages.firstOrNull()?.timestampMillis ?: System.currentTimeMillis(), messageId)
                } else {
                    if (isDefaultSmsApp && intent.action == Telephony.Sms.Intents.SMS_DELIVER_ACTION) {
                         saveIncomingMessages(context, messages)
                    }
                    showNotification(context, sender, bodyStr)
                }
            }
        }
    }

    private fun saveIncomingMessages(context: Context, messages: Array<android.telephony.SmsMessage>): Long {
        val inboxUri = Uri.parse("content://sms/inbox")
        var insertedId = -1L
        for (msg in messages) {
            try {
                val values = ContentValues().apply {
                    put(Telephony.Sms.ADDRESS, msg.displayOriginatingAddress)
                    put(Telephony.Sms.BODY, msg.displayMessageBody)
                    put(Telephony.Sms.DATE, msg.timestampMillis)
                    put(Telephony.Sms.READ, 0)
                    put(Telephony.Sms.SEEN, 0)
                    put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_INBOX)
                }
                val uri = context.contentResolver.insert(inboxUri, values)
                insertedId = uri?.lastPathSegment?.toLongOrNull() ?: insertedId
            } catch (_: Exception) {}
        }
        return insertedId
    }

    private fun scheduleOtpDeletion(context: Context, address: String, timestamp: Long, messageId: Long) {
        val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(PREF_OTP_AUTO_DELETE, true)) return

        // Flutter's SharedPreferences stores integers as Long on Android. 
        // We use a safe cast from Number to avoid ClassCastException.
        val deleteMinutes = (prefs.all[PREF_OTP_DELETE_MINUTES] as? Number)?.toInt() ?: DEFAULT_DELETE_MINUTES

        val deleteAfterMs = deleteMinutes * 60 * 1000L

        val deleteIntent = Intent(context, OtpDeleteReceiver::class.java).apply {
            putExtra("otp_address", address)
            putExtra("otp_timestamp", timestamp)
            putExtra("otp_id", messageId)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context, (address + timestamp).hashCode(), deleteIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAt = System.currentTimeMillis() + deleteAfterMs
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        } else {
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        }
    }

    private fun createChannels(context: Context, notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val smsChannel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Notifications for incoming SMS messages"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(smsChannel)

            val otpChannel = NotificationChannel(OTP_CHANNEL_ID, OTP_CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Secure OTP notifications"
                enableVibration(true)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PRIVATE
                
                // Custom sound for OTP notifications
                val audioAttributes = android.media.AudioAttributes.Builder()
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
                    .build()
                val soundUri = android.net.Uri.parse("android.resource://" + context.packageName + "/" + R.raw.otp_sms)
                setSound(soundUri, audioAttributes)
            }
            notificationManager.createNotificationChannel(otpChannel)
        }
    }

    private fun showOtpNotification(context: Context, sender: String, body: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createChannels(context, notificationManager)

        val otp = extractOtp(body) ?: "------"

        // Intent to open app
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("sms_address", sender)
        }
        val pendingIntent = PendingIntent.getActivity(
            context, sender.hashCode(), openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Intent to copy OTP
        val copyIntent = Intent(context, OtpActionReceiver::class.java).apply {
            action = "ACTION_COPY_OTP"
            putExtra("otp_code", otp)
            putExtra("otp_sender", sender)
        }
        val copyPendingIntent = PendingIntent.getBroadcast(
            context, (sender + otp).hashCode(), copyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Custom Layout via RemoteViews
        val remoteViews = RemoteViews(context.packageName, R.layout.notification_otp)
        remoteViews.setTextViewText(R.id.otp_code, otp)
        remoteViews.setTextViewText(R.id.notification_title, "OTP • $sender")
        remoteViews.setTextViewText(R.id.otp_sender, "Don't share your OTP with anyone")
        remoteViews.setOnClickPendingIntent(R.id.btn_copy, copyPendingIntent)

        val notification = NotificationCompat.Builder(context, OTP_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_action_email)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setCustomContentView(remoteViews)
            .setCustomBigContentView(remoteViews)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setPublicVersion(
                NotificationCompat.Builder(context, OTP_CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.sym_action_email)
                    .setContentTitle("New OTP")
                    .setContentText("Tap to view your code")
                    .build()
            )
            .setDefaults(Notification.DEFAULT_ALL)
            .build()

        notificationManager.notify(sender.hashCode(), notification)
    }

    private fun showNotification(context: Context, sender: String, body: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createChannels(context, notificationManager)

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("sms_address", sender)
        }
        val pendingIntent = PendingIntent.getActivity(
            context, sender.hashCode(), openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_action_email)
            .setContentTitle(sender)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setDefaults(Notification.DEFAULT_ALL)
            .build()

        notificationManager.notify(sender.hashCode(), notification)
    }
}
