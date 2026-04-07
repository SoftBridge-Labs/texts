package `in`.softbridgelabs.text

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.SmsManager

/**
 * Triggered by AlarmManager to send a scheduled SMS at the user-configured time.
 */
class ScheduledSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val address = intent.getStringExtra("sms_address") ?: return
        val body    = intent.getStringExtra("sms_body")    ?: return
        try {
            val smsManager: SmsManager = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            val parts = smsManager.divideMessage(body)
            smsManager.sendMultipartTextMessage(address, null, parts, null, null)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
