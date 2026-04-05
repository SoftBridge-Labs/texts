package `in`.softbridgelabs.text

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.ClipboardManager
import android.content.ClipData
import android.widget.Toast
import android.app.NotificationManager

class OtpActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "ACTION_COPY_OTP") {
            val otpCode = intent.getStringExtra("otp_code")
            val sender = intent.getStringExtra("otp_sender")
            
            if (otpCode != null) {
                val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clip = ClipData.newPlainText("OTP Code", otpCode)
                clipboard.setPrimaryClip(clip)
                
                Toast.makeText(context, "OTP Copied: $otpCode", Toast.LENGTH_SHORT).show()
                
                // Dimiss notification
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(sender.hashCode())
            }
        }
    }
}
