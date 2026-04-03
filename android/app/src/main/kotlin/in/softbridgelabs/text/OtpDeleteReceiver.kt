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
        if (timestamp == -1L) return

        try {
            val uri = Uri.parse("content://sms/inbox")
            val selection = "${Telephony.Sms.ADDRESS} = ? AND ${Telephony.Sms.DATE} = ?"
            val args = arrayOf(address, timestamp.toString())
            context.contentResolver.delete(uri, selection, args)
        } catch (_: Exception) {
            // Ignore – message may already be gone
        }
    }
}
