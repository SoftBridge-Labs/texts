package `in`.softbridgelabs.text

import android.app.role.RoleManager
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle
import android.content.SharedPreferences

class MainActivity: FlutterActivity() {
    private val CHANNEL = "in.softbridgelabs.text/default_sms"
    private var resultCallback: MethodChannel.Result? = null
    private val REQUEST_CODE_DEFAULT_SMS = 1001
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Screenshot protection is controlled by user setting via flutter_windowmanager
    }

    override fun onResume() {
        super.onResume()
        // On app foreground: check if any OTP messages are past their auto-delete time
        checkAndDeleteExpiredOtpMessages()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "isDefaultSmsApp" -> result.success(isDefaultSmsApp())
                "requestDefaultSmsApp" -> {
                    resultCallback = result
                    requestDefaultSmsApp()
                }
                "getMessagesForAddress" -> {
                    val address = call.argument<String>("address")
                    if (address != null) {
                        result.success(getMessagesForAddress(address))
                    } else {
                        result.error("INVALID_ARGUMENT", "Address is null", null)
                    }
                }
                "getMmsForAddress" -> {
                    val address = call.argument<String>("address")
                    if (address != null) {
                        result.success(getMmsForAddress(address))
                    } else {
                        result.error("INVALID_ARGUMENT", "Address is null", null)
                    }
                }
                "getAllConversations" -> {
                    result.success(getAllConversations())
                }
                "markSmsAsRead" -> {
                    val address = call.argument<String>("address")
                    if (address != null) {
                        val updated = markSmsAsRead(address)
                        result.success(updated)
                    } else {
                        result.error("INVALID_ARGUMENT", "Address is null", null)
                    }
                }
                "getInitialSmsAddress" -> {
                    result.success(getAndClearSmsAddress(intent))
                }
                "deleteSmsMessage" -> {
                    val id = call.argument<Int>("id")
                    if (id != null) {
                        val deleted = deleteSmsMessageById(id)
                        result.success(deleted)
                    } else {
                        val address = call.argument<String>("address")
                        val timestamp = call.argument<Long>("timestamp")
                        if (address != null && timestamp != null) {
                            val deleted = deleteSmsMessage(address, timestamp)
                            result.success(deleted)
                        } else {
                            result.error("INVALID_ARGUMENT", "ID or Address/Timestamp is null", null)
                        }
                    }
                }
                "deleteSmsThread" -> {
                    val address = call.argument<String>("address")
                    if (address != null) {
                        val deleted = deleteSmsThread(address)
                        result.success(deleted)
                    } else {
                        result.error("INVALID_ARGUMENT", "Address is null", null)
                    }
                }
                "scheduleSms" -> {
                    val address = call.argument<String>("address")
                    val body = call.argument<String>("body")
                    val scheduledMs = call.argument<Long>("scheduledMs")
                    if (address != null && body != null && scheduledMs != null) {
                        scheduleSmsSend(address, body, scheduledMs)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Missing arguments for scheduleSms", null)
                    }
                }
                "checkOtpExpiry" -> {
                    val deleted = checkAndDeleteExpiredOtpMessages()
                    result.success(deleted)
                }
                "canReplyToAddress" -> {
                    val address = call.argument<String>("address")
                    result.success(canReplyToAddress(address))
                }
                "searchMessages" -> {
                    val query = call.argument<String>("query") ?: ""
                    result.success(searchMessages(query))
                }
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "URL is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * On app open, scan SMS inbox for any OTP messages that have passed
     * their configured auto-delete window and delete them immediately.
     * This is the reliable fallback for when AlarmManager fires late / is cancelled.
     */
    private fun checkAndDeleteExpiredOtpMessages(): Int {
        val prefs: SharedPreferences = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        if (!prefs.getBoolean("flutter.otp_auto_delete_enabled", true)) return 0

        // Flutter's SharedPreferences stores integers as Long on Android. 
        // We use a safe cast from Number to avoid ClassCastException.
        val deleteMinutes = (prefs.all["flutter.otp_delete_minutes"] as? Number)?.toInt() ?: 10

        val deleteAfterMs = deleteMinutes * 60 * 1000L
        val cutoffTime = System.currentTimeMillis() - deleteAfterMs

        var totalDeleted = 0
        try {
            val uri = Uri.parse("content://sms/inbox")
            val projection = arrayOf(
                Telephony.Sms._ID,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE
            )
            // Only look at messages newer than 24 hours to keep query fast
            val selection = "${Telephony.Sms.DATE} > ?"
            val oneDayAgo = (System.currentTimeMillis() - 24 * 60 * 60 * 1000L).toString()

            val cursor = contentResolver.query(uri, projection, selection, arrayOf(oneDayAgo), null)
            cursor?.use { c ->
                val idIdx   = c.getColumnIndexOrThrow(Telephony.Sms._ID)
                val bodyIdx = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
                val dateIdx = c.getColumnIndexOrThrow(Telephony.Sms.DATE)

                while (c.moveToNext()) {
                    val id   = c.getLong(idIdx)
                    val body = c.getString(bodyIdx) ?: continue
                    val date = c.getLong(dateIdx)

                    // If this is an OTP message AND it was received before the cutoff time → delete
                    if (SmsReceiver.isOtpMessage(body) && date <= cutoffTime) {
                        val deleteUri = Uri.parse("content://sms/$id")
                        val d = contentResolver.delete(deleteUri, null, null)
                        totalDeleted += d
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return totalDeleted
    }

    /**
     * Returns true if we can send an SMS reply to this address.
     * Broadcast numbers (5-digit short codes starting with specific patterns,
     * or addresses that have ONLY received traffic — no sent messages) may not support replies.
     */
    private fun canReplyToAddress(address: String?): Boolean {
        if (address == null) return false
        // Short-code heuristic — numeric-only addresses of 5-6 digits are usually broadcast
        val digits = address.filter { it.isDigit() }
        if (address.all { it.isDigit() || it == '-' } && digits.length in 4..6) return false
        // Also check if there are any sent messages in this thread
        return try {
            val uri = Uri.parse("content://sms/sent")
            val cursor = contentResolver.query(
                uri, arrayOf(Telephony.Sms._ID),
                "${Telephony.Sms.ADDRESS} = ?", arrayOf(address),
                null
            )
            val hasSent = (cursor?.count ?: 0) > 0
            cursor?.close()
            hasSent || !address.all { it.isDigit() || it == '+' || it == '-' || it == ' ' }
        } catch (e: Exception) {
            true // default: allow reply
        }
    }

    /**
     * Full-text search across SMS messages.
     */
    private fun searchMessages(query: String): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        if (query.isBlank()) return results
        try {
            val uri = Uri.parse("content://sms")
            val projection = arrayOf(
                Telephony.Sms._ID,
                Telephony.Sms.ADDRESS,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE,
                Telephony.Sms.TYPE
            )
            val cursor = contentResolver.query(
                uri, projection,
                "${Telephony.Sms.BODY} LIKE ?",
                arrayOf("%$query%"),
                "${Telephony.Sms.DATE} DESC LIMIT 200"
            )
            cursor?.use { c ->
                val idIdx   = c.getColumnIndexOrThrow(Telephony.Sms._ID)
                val addrIdx = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
                val bodyIdx = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
                val dateIdx = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
                val typeIdx = c.getColumnIndexOrThrow(Telephony.Sms.TYPE)
                while (c.moveToNext()) {
                    results.add(mapOf(
                        "id"      to c.getInt(idIdx),
                        "address" to c.getString(addrIdx),
                        "body"    to c.getString(bodyIdx),
                        "date"    to c.getLong(dateIdx),
                        "type"    to c.getInt(typeIdx)
                    ))
                }
            }
        } catch (e: Exception) { /* ignore */ }
        return results
    }

    /**
     * Schedule an SMS send via AlarmManager.
     */
    private fun scheduleSmsSend(address: String, body: String, scheduledMs: Long) {
        val intent = Intent(this, ScheduledSmsReceiver::class.java).apply {
            putExtra("sms_address", address)
            putExtra("sms_body", body)
        }
        val pi = android.app.PendingIntent.getBroadcast(
            this, (address + scheduledMs).hashCode(), intent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        val am = getSystemService(ALARM_SERVICE) as android.app.AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, scheduledMs, pi)
        } else {
            am.setExact(android.app.AlarmManager.RTC_WAKEUP, scheduledMs, pi)
        }
    }

    /**
     * Query MMS messages for a given address (thread participant).
     */
    private fun getMmsForAddress(address: String): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        try {
            // Find thread IDs containing this address
            val threadCursor = contentResolver.query(
                Uri.parse("content://mms-sms/conversations"),
                null, null, null, null
            )
            val threadIds = mutableSetOf<Long>()
            threadCursor?.use { tc ->
                val tidIdx = tc.getColumnIndex("thread_id")
                val addrIdx = tc.getColumnIndex(Telephony.Sms.ADDRESS)
                while (tc.moveToNext()) {
                    if (tidIdx != -1 && addrIdx != -1) {
                        val addr = tc.getString(addrIdx) ?: continue
                        if (addr.contains(address) || address.contains(addr)) {
                            threadIds.add(tc.getLong(tidIdx))
                        }
                    }
                }
            }

            for (threadId in threadIds) {
                val mmsCursor = contentResolver.query(
                    Uri.parse("content://mms"),
                    arrayOf(Telephony.Mms._ID, Telephony.Mms.DATE, Telephony.Mms.MESSAGE_BOX, Telephony.Mms.READ),
                    "${Telephony.Mms.THREAD_ID} = ?",
                    arrayOf(threadId.toString()),
                    "${Telephony.Mms.DATE} DESC LIMIT 50"
                )
                mmsCursor?.use { mc ->
                    val idIdx   = mc.getColumnIndexOrThrow(Telephony.Mms._ID)
                    val dateIdx = mc.getColumnIndexOrThrow(Telephony.Mms.DATE)
                    val boxIdx  = mc.getColumnIndexOrThrow(Telephony.Mms.MESSAGE_BOX)
                    val readIdx = mc.getColumnIndexOrThrow(Telephony.Mms.READ)
                    while (mc.moveToNext()) {
                        val mmsId = mc.getLong(idIdx)
                        val partText = getMmsTextPart(mmsId)
                        val partImages = getMmsImageParts(mmsId)
                        results.add(mapOf(
                            "id"          to mmsId,
                            "address"     to address,
                            "body"        to (partText ?: "📎 Multimedia Message"),
                            "date"        to mc.getLong(dateIdx) * 1000L, // MMS date is in seconds
                            "type"        to mc.getInt(boxIdx),
                            "read"        to (mc.getInt(readIdx) == 1),
                            "isMms"       to true,
                            "hasImages"   to partImages.isNotEmpty(),
                            "imageParts"  to partImages
                        ))
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return results
    }

    private fun getMmsTextPart(mmsId: Long): String? {
        return try {
            val cursor = contentResolver.query(
                Uri.parse("content://mms/$mmsId/part"),
                arrayOf(Telephony.Mms.Part._ID, Telephony.Mms.Part.CONTENT_TYPE, Telephony.Mms.Part.TEXT),
                null, null, null
            )
            var text: String? = null
            cursor?.use { c ->
                val typeIdx = c.getColumnIndexOrThrow(Telephony.Mms.Part.CONTENT_TYPE)
                val textIdx = c.getColumnIndex(Telephony.Mms.Part.TEXT)
                val idIdx   = c.getColumnIndexOrThrow(Telephony.Mms.Part._ID)
                while (c.moveToNext()) {
                    val ct = c.getString(typeIdx)
                    if (ct?.startsWith("text/") == true) {
                        if (textIdx != -1) {
                            text = c.getString(textIdx)
                        }
                        if (text.isNullOrEmpty()) {
                            val partId = c.getLong(idIdx)
                            val partUri = Uri.parse("content://mms/part/$partId")
                            text = contentResolver.openInputStream(partUri)?.bufferedReader()?.readText()
                        }
                        if (!text.isNullOrEmpty()) break
                    }
                }
            }
            text
        } catch (e: Exception) {
            null
        }
    }

    private fun getMmsImageParts(mmsId: Long): List<String> {
        val uris = mutableListOf<String>()
        try {
            val cursor = contentResolver.query(
                Uri.parse("content://mms/$mmsId/part"),
                arrayOf(Telephony.Mms.Part._ID, Telephony.Mms.Part.CONTENT_TYPE),
                null, null, null
            )
            cursor?.use { c ->
                val typeIdx = c.getColumnIndexOrThrow(Telephony.Mms.Part.CONTENT_TYPE)
                val idIdx   = c.getColumnIndexOrThrow(Telephony.Mms.Part._ID)
                while (c.moveToNext()) {
                    val ct = c.getString(typeIdx) ?: continue
                    if (ct.startsWith("image/") || ct.startsWith("video/")) {
                        uris.add("content://mms/part/${c.getLong(idIdx)}")
                    }
                }
            }
        } catch (e: Exception) { /* ignore */ }
        return uris
    }

    private fun getMessagesForAddress(address: String): List<Map<String, Any?>> {
        val messages = mutableListOf<Map<String, Any?>>()
        try {
            val uri = Uri.parse("content://sms")
            val selection = "${Telephony.Sms.ADDRESS} = ?"
            val selectionArgs = arrayOf(address)
            val projection = arrayOf(
                Telephony.Sms._ID,
                Telephony.Sms.ADDRESS,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE,
                Telephony.Sms.TYPE,
                Telephony.Sms.READ
            )
            val cursor = contentResolver.query(uri, projection, selection, selectionArgs, "${Telephony.Sms.DATE} DESC LIMIT 400")
            cursor?.use { c ->
                val idIdx   = c.getColumnIndexOrThrow(Telephony.Sms._ID)
                val addrIdx = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
                val bodyIdx = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
                val dateIdx = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
                val typeIdx = c.getColumnIndexOrThrow(Telephony.Sms.TYPE)
                val readIdx = c.getColumnIndexOrThrow(Telephony.Sms.READ)

                while (c.moveToNext()) {
                    messages.add(mapOf(
                        "id"      to c.getInt(idIdx),
                        "address" to c.getString(addrIdx),
                        "body"    to c.getString(bodyIdx),
                        "date"    to c.getLong(dateIdx),
                        "type"    to c.getInt(typeIdx),
                        "read"    to (c.getInt(readIdx) == 1),
                        "isMms"   to false
                    ))
                }
            }
        } catch (e: Exception) { /* ignore */ }
        return messages
    }

    private fun getAllConversations(): List<Map<String, Any?>> {
        val conversations = mutableListOf<Map<String, Any?>>()
        try {
            val uri = Uri.parse("content://sms/conversations")
            val projection = arrayOf(
                "snippet",
                Telephony.Sms.ADDRESS,
                Telephony.Sms.DATE,
                Telephony.Sms.TYPE,
                Telephony.Sms.READ,
                Telephony.Sms.THREAD_ID
            )
            val cursor = contentResolver.query(uri, projection, null, null, "date DESC LIMIT 300")
            
            cursor?.use { c ->
                val bodyIdx   = c.getColumnIndex("snippet")
                val addrIdx   = c.getColumnIndex(Telephony.Sms.ADDRESS)
                val dateIdx   = c.getColumnIndex(Telephony.Sms.DATE)
                val typeIdx   = c.getColumnIndex(Telephony.Sms.TYPE)
                val readIdx   = c.getColumnIndex(Telephony.Sms.READ)
                val threadIdx = c.getColumnIndex(Telephony.Sms.THREAD_ID)

                while (c.moveToNext()) {
                    val threadId = if (threadIdx != -1) c.getLong(threadIdx) else 0L
                    var address = if (addrIdx != -1) c.getString(addrIdx) else null
                    
                    if (address == null && threadId != 0L) {
                        try {
                            val msgCursor = contentResolver.query(
                                Uri.parse("content://sms"),
                                arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.DATE),
                                "${Telephony.Sms.THREAD_ID} = ?",
                                arrayOf(threadId.toString()),
                                "date DESC LIMIT 1"
                            )
                            msgCursor?.use { mc ->
                                if (mc.moveToFirst()) address = mc.getString(0)
                            }
                        } catch (_: Exception) {}
                    }

                    conversations.add(mapOf(
                        "body"      to (if (bodyIdx != -1) c.getString(bodyIdx) else ""),
                        "address"   to (address ?: "Unknown"),
                        "date"      to (if (dateIdx != -1) c.getLong(dateIdx) else System.currentTimeMillis()),
                        "type"      to (if (typeIdx != -1) c.getInt(typeIdx) else 1),
                        "read"      to (if (readIdx != -1) c.getInt(readIdx) == 1 else true),
                        "thread_id" to threadId
                    ))
                }
            }
        } catch (e: Exception) {
            return getFallbackConversations()
        }
        return conversations
    }

    private fun getFallbackConversations(): List<Map<String, Any?>> {
        val conversations = mutableListOf<Map<String, Any?>>()
        val seenThreads = mutableSetOf<Long>()
        try {
            val uri = Uri.parse("content://sms")
            val projection = arrayOf(
                Telephony.Sms.BODY,
                Telephony.Sms.ADDRESS,
                Telephony.Sms.DATE,
                Telephony.Sms.TYPE,
                Telephony.Sms.READ,
                Telephony.Sms.THREAD_ID
            )
            val cursor = contentResolver.query(uri, projection, null, null, "date DESC LIMIT 300")
            cursor?.use { c ->
                val bodyIdx   = c.getColumnIndex(Telephony.Sms.BODY)
                val addrIdx   = c.getColumnIndex(Telephony.Sms.ADDRESS)
                val dateIdx   = c.getColumnIndex(Telephony.Sms.DATE)
                val typeIdx   = c.getColumnIndex(Telephony.Sms.TYPE)
                val readIdx   = c.getColumnIndex(Telephony.Sms.READ)
                val threadIdx = c.getColumnIndex(Telephony.Sms.THREAD_ID)
                
                while (c.moveToNext()) {
                    val threadId = c.getLong(threadIdx)
                    if (!seenThreads.contains(threadId)) {
                        seenThreads.add(threadId)
                        conversations.add(mapOf(
                            "body"      to c.getString(bodyIdx),
                            "address"   to (c.getString(addrIdx) ?: "Unknown"),
                            "date"      to c.getLong(dateIdx),
                            "type"      to c.getInt(typeIdx),
                            "read"      to (c.getInt(readIdx) == 1),
                            "thread_id" to threadId
                        ))
                    }
                }
            }
        } catch (_: Exception) {}
        return conversations
    }

    private fun getAndClearSmsAddress(intent: Intent?): String? {
        val address = intent?.getStringExtra("sms_address")
        intent?.removeExtra("sms_address")
        return address
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val address = getAndClearSmsAddress(intent)
        if (address != null) {
            methodChannel?.invokeMethod("onNotificationTap", address)
        }

        // Handle emergency alert deep-link
        if (intent.getBooleanExtra("show_emergency_alert", false)) {
            val title = intent.getStringExtra("alert_title") ?: "Emergency Alert"
            val body  = intent.getStringExtra("alert_body") ?: ""
            methodChannel?.invokeMethod("onEmergencyAlert", mapOf("title" to title, "body" to body))
        }
    }

    private fun isDefaultSmsApp(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(RoleManager::class.java)
            roleManager?.isRoleHeld(RoleManager.ROLE_SMS) == true
        } else {
            val defaultSmsPackage = Telephony.Sms.getDefaultSmsPackage(this)
            defaultSmsPackage != null && defaultSmsPackage == packageName
        }
    }

    private fun requestDefaultSmsApp() {
        if (isDefaultSmsApp()) {
            resultCallback?.success(true)
            resultCallback = null
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = getSystemService(RoleManager::class.java)
                if (roleManager != null && roleManager.isRoleAvailable(RoleManager.ROLE_SMS)) {
                    val roleIntent = roleManager.createRequestRoleIntent(RoleManager.ROLE_SMS)
                    startActivityForResult(roleIntent, REQUEST_CODE_DEFAULT_SMS)
                    return
                }
            }
            val intent = Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT)
            intent.putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, packageName)
            startActivityForResult(intent, REQUEST_CODE_DEFAULT_SMS)
        } catch (e: Exception) {
            resultCallback?.success(false)
            resultCallback = null
        }
    }

    private fun markSmsAsRead(address: String): Int {
        return try {
            val values = ContentValues()
            values.put(Telephony.Sms.READ, 1)
            values.put(Telephony.Sms.SEEN, 1)
            val uri = Uri.parse("content://sms/inbox")
            val selection = "${Telephony.Sms.ADDRESS} = ? AND ${Telephony.Sms.READ} = 0"
            val selectionArgs = arrayOf(address)
            val count = contentResolver.update(uri, values, selection, selectionArgs)
            if (count == 0) {
                contentResolver.update(Uri.parse("content://sms"), values, selection, selectionArgs)
            } else {
                count
            }
        } catch (e: Exception) {
            0
        }
    }

    private fun deleteSmsMessageById(id: Int): Int {
        return try {
            val uri = Uri.parse("content://sms/$id")
            contentResolver.delete(uri, null, null)
        } catch (e: Exception) {
            0
        }
    }

    private fun deleteSmsMessage(address: String, timestamp: Long): Int {
        return try {
            val uri = Uri.parse("content://sms")
            contentResolver.delete(
                uri,
                "${Telephony.Sms.ADDRESS} = ? AND ${Telephony.Sms.DATE} = ?",
                arrayOf(address, timestamp.toString())
            )
        } catch (e: Exception) {
            0
        }
    }

    private fun deleteSmsThread(address: String): Int {
        return try {
            val uri = Uri.parse("content://sms")
            contentResolver.delete(
                uri,
                "${Telephony.Sms.ADDRESS} = ?",
                arrayOf(address)
            )
        } catch (e: Exception) {
            0
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_DEFAULT_SMS) {
            resultCallback?.success(isDefaultSmsApp())
            resultCallback = null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
    }
}



