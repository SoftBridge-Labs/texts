package `in`.softbridgelabs.text

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Telephony

/**
 * Triggered by AlarmManager to delete an OTP message after the configured delay.
 */
class OtpDeleteReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val address = intent.getStringExtra("otp_address") ?: return
        val timestamp = intent.getLongExtra("otp_timestamp", -1L)
        val messageId = intent.getLongExtra("otp_id", -1L)

        try {
            var deletedCount = 0
            if (messageId != -1L) {
                val uri = Uri.parse("content://sms/$messageId")
                deletedCount = context.contentResolver.delete(uri, null, null)
            }
            
            // Fallback to searching by address and timestamp if ID deletion didn't happen or failed
            if (deletedCount == 0 && timestamp != -1L) {
                val uri = Uri.parse("content://sms/inbox")
                val selection = "${Telephony.Sms.ADDRESS} = ? AND ${Telephony.Sms.DATE} = ?"
                val args = arrayOf(address, timestamp.toString())
                context.contentResolver.delete(uri, selection, args)
            }
            
            // Also cancel the notification
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            notificationManager.cancel(address.hashCode())
        } catch (_: Exception) {
            // Ignore – message may already be gone
        }
    }
}
