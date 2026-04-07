package `in`.softbridgelabs.text

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Telephony
import androidx.core.app.NotificationCompat

/**
 * Handles incoming MMS (WAP_PUSH_DELIVER) messages.
 * Saves them to the system MMS content-provider and shows a notification.
 */
class MmsReceiver : BroadcastReceiver() {

    companion object {
        private const val MMS_CHANNEL_ID = "mms_channel"
        private const val MMS_CHANNEL_NAME = "MMS Notifications"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Telephony.Sms.Intents.WAP_PUSH_DELIVER_ACTION &&
            action != "android.provider.Telephony.WAP_PUSH_RECEIVED") return

        val mimeType = intent.type ?: return
        if (!mimeType.equals("application/vnd.wap.mms-message", ignoreCase = true)) return

        // Only handle if we are the default SMS app
        val isDefault = Telephony.Sms.getDefaultSmsPackage(context) == context.packageName
        if (!isDefault) return

        try {
            val data = intent.getByteArrayExtra("data") ?: return
            processIncomingMms(context, data, intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun processIncomingMms(context: Context, data: ByteArray, intent: Intent) {
        // Parse sender from WAP push headers (address comes from push headers or PDU)
        val sender = intent.getStringExtra("address") ?: "Unknown"

        // Save raw MMS PDU to system inbox so it appears in content://mms
        saveMmsPdu(context, data, sender)

        // Show notification
        showMmsNotification(context, sender, "Multimedia message received")
    }

    private fun saveMmsPdu(context: Context, pdu: ByteArray, sender: String) {
        try {
            val values = ContentValues().apply {
                put(Telephony.Mms.MESSAGE_BOX, Telephony.Mms.MESSAGE_BOX_INBOX)
                put(Telephony.Mms.READ, 0)
                put(Telephony.Mms.SEEN, 0)
                put(Telephony.Mms.DATE, System.currentTimeMillis() / 1000L)
                put(Telephony.Mms.CONTENT_TYPE, "application/vnd.wap.multipart.related")
                put("msg_box", 1)
            }
            val uri = context.contentResolver.insert(Uri.parse("content://mms"), values)

            if (uri != null) {
                // Save the raw PDU bytes as a part
                val partValues = ContentValues().apply {
                    put(Telephony.Mms.Part.MSG_ID, uri.lastPathSegment)
                    put(Telephony.Mms.Part.CONTENT_TYPE, "application/octet-stream")
                    put(Telephony.Mms.Part.NAME, "pdu.bin")
                }
                val partUri = Uri.parse("content://mms/${uri.lastPathSegment}/part")
                val partInsertUri = context.contentResolver.insert(partUri, partValues)
                if (partInsertUri != null) {
                    context.contentResolver.openOutputStream(partInsertUri)?.use { os ->
                        os.write(pdu)
                    }
                }

                // Save sender address
                val addrValues = ContentValues().apply {
                    put(Telephony.Mms.Addr.MSG_ID, uri.lastPathSegment)
                    put(Telephony.Mms.Addr.ADDRESS, sender)
                    put(Telephony.Mms.Addr.TYPE, 137) // TYPE_FROM = 137
                    put(Telephony.Mms.Addr.CHARSET, 3) // UTF-8
                }
                val addrUri = Uri.parse("content://mms/${uri.lastPathSegment}/addr")
                context.contentResolver.insert(addrUri, addrValues)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun showMmsNotification(context: Context, sender: String, body: String) {
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createChannel(context, notificationManager)

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("sms_address", sender)
        }
        val pendingIntent = PendingIntent.getActivity(
            context, sender.hashCode(), openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, MMS_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_action_email)
            .setContentTitle("MMS • $sender")
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setDefaults(Notification.DEFAULT_ALL)
            .build()

        notificationManager.notify(("mms_$sender").hashCode(), notification)
    }

    private fun createChannel(context: Context, nm: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(MMS_CHANNEL_ID, MMS_CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH).apply {
                description = "MMS message notifications"
                enableVibration(true)
            }
            nm.createNotificationChannel(ch)
        }
    }
}
