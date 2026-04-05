package `in`.softbridgelabs.text

import android.app.role.RoleManager
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Telephony
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle

class MainActivity: FlutterActivity() {
    private val CHANNEL = "in.softbridgelabs.text/default_sms"
    private var resultCallback: MethodChannel.Result? = null
    private val REQUEST_CODE_DEFAULT_SMS = 1001
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block screenshots/screen mirror/sharing of content
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
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
                else -> result.notImplemented()
            }
        }
    }

    private fun getMessagesForAddress(address: String): List<Map<String, Any?>> {
        val messages = mutableListOf<Map<String, Any?>>()
        try {
            // Find messages by address in system DB directly — much faster than querying all in first place
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
                val idIdx = c.getColumnIndexOrThrow(Telephony.Sms._ID)
                val addrIdx = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
                val bodyIdx = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
                val dateIdx = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
                val typeIdx = c.getColumnIndexOrThrow(Telephony.Sms.TYPE)
                val readIdx = c.getColumnIndexOrThrow(Telephony.Sms.READ)

                while (c.moveToNext()) {
                    messages.add(mapOf(
                        "id" to c.getInt(idIdx),
                        "address" to c.getString(addrIdx),
                        "body" to c.getString(bodyIdx),
                        "date" to c.getLong(dateIdx),
                        "type" to c.getInt(typeIdx),
                        "read" to (c.getInt(readIdx) == 1)
                    ))
                }
            }
        } catch (e: Exception) {
            // Log or ignore
        }
        return messages
    }

    private fun getAllConversations(): List<Map<String, Any?>> {
        val conversations = mutableListOf<Map<String, Any?>>()
        try {
            // Using content://sms/conversations to leverage system-side grouping for speed
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
                val bodyIdx = c.getColumnIndex("snippet") // Conversations view uses 'snippet' for latest msg body
                val addrIdx = c.getColumnIndex(Telephony.Sms.ADDRESS)
                val dateIdx = c.getColumnIndex(Telephony.Sms.DATE)
                val typeIdx = c.getColumnIndex(Telephony.Sms.TYPE)
                val readIdx = c.getColumnIndex(Telephony.Sms.READ)
                val threadIdx = c.getColumnIndex(Telephony.Sms.THREAD_ID)

                while (c.moveToNext()) {
                    val threadId = if (threadIdx != -1) c.getLong(threadIdx) else 0L
                    var address = if (addrIdx != -1) c.getString(addrIdx) else null
                    
                    // If address is missing in the conversation view, we fetch the latest message details for this thread
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
                                if (mc.moveToFirst()) {
                                    address = mc.getString(0)
                                }
                            }
                        } catch (_: Exception) {}
                    }

                    conversations.add(mapOf(
                        "body" to (if (bodyIdx != -1) c.getString(bodyIdx) else ""),
                        "address" to (address ?: "Unknown"),
                        "date" to (if (dateIdx != -1) c.getLong(dateIdx) else System.currentTimeMillis()),
                        "type" to (if (typeIdx != -1) c.getInt(typeIdx) else 1),
                        "read" to (if (readIdx != -1) c.getInt(readIdx) == 1 else true),
                        "thread_id" to threadId
                    ))
                }
            }
        } catch (e: Exception) {
            // If the specialized query fails, fallback to a limited manual group logic
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
            // Limit to last 300 messages for fallback to ensure performance
            val cursor = contentResolver.query(uri, projection, null, null, "date DESC LIMIT 300")
            cursor?.use { c ->
                val bodyIdx = c.getColumnIndex(Telephony.Sms.BODY)
                val addrIdx = c.getColumnIndex(Telephony.Sms.ADDRESS)
                val dateIdx = c.getColumnIndex(Telephony.Sms.DATE)
                val typeIdx = c.getColumnIndex(Telephony.Sms.TYPE)
                val readIdx = c.getColumnIndex(Telephony.Sms.READ)
                val threadIdx = c.getColumnIndex(Telephony.Sms.THREAD_ID)
                
                while (c.moveToNext()) {
                    val threadId = c.getLong(threadIdx)
                    if (!seenThreads.contains(threadId)) {
                        seenThreads.add(threadId)
                        conversations.add(mapOf(
                            "body" to c.getString(bodyIdx),
                            "address" to (c.getString(addrIdx) ?: "Unknown"),
                            "date" to c.getLong(dateIdx),
                            "type" to c.getInt(typeIdx),
                            "read" to (c.getInt(readIdx) == 1),
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
                // Fallback to general SMS table if inbox update did not affect any rows
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
}
