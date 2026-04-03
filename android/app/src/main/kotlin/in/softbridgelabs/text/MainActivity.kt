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

class MainActivity: FlutterActivity() {
    private val CHANNEL = "in.softbridgelabs.text/default_sms"
    private var resultCallback: MethodChannel.Result? = null
    private val REQUEST_CODE_DEFAULT_SMS = 1001
    private var methodChannel: MethodChannel? = null

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
            val uri = Uri.parse("content://sms")
            val selection = "${Telephony.Sms.ADDRESS} = ? AND ${Telephony.Sms.READ} = 0"
            val selectionArgs = arrayOf(address)
            contentResolver.update(uri, values, selection, selectionArgs)
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
