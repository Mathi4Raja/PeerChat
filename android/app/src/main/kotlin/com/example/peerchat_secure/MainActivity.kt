package com.example.peerchat_secure

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.provider.Settings
import android.provider.MediaStore
import android.net.Uri
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import java.io.ByteArrayOutputStream
import android.content.BroadcastReceiver
import android.bluetooth.BluetoothAdapter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.net.wifi.WifiManager

class MainActivity : FlutterActivity() {
    companion object {
        private const val DEVICE_STATUS_CHANNEL = "peerchat_secure/device_status"
        private const val BLUETOOTH_STATE_CHANNEL = "peerchat_secure/bluetooth_state"
    }

    private var bluetoothReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_STATUS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBatteryStatus" -> {
                    val batteryManager =
                        getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val level = batteryManager.getIntProperty(
                        BatteryManager.BATTERY_PROPERTY_CAPACITY
                    )
                    val status = batteryManager.getIntProperty(
                        BatteryManager.BATTERY_PROPERTY_STATUS
                    )
                    val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                        status == BatteryManager.BATTERY_STATUS_FULL

                    result.success(
                        mapOf(
                            "level" to level,
                            "isCharging" to isCharging
                        )
                    )
                }

                "getAppIcon" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        try {
                            val pm = packageManager
                            val icon = pm.getApplicationIcon(packageName)
                            val bitmap = drawableToBitmap(icon)
                            
                            val scaledBitmap = Bitmap.createScaledBitmap(bitmap, 128, 128, true)
                            
                            val stream = ByteArrayOutputStream()
                            scaledBitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                            result.success(stream.toByteArray())
                        } catch (e: Exception) {
                            result.error("ICON_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Package name is null", null)
                    }
                }

                "openLocationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }

                "checkSystemSettingsPermission" -> {
                    result.success(Settings.System.canWrite(this))
                }

                "openSystemSettingsPermission" -> {
                    try {
                        val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                        intent.data = android.net.Uri.parse("package:$packageName")
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "toggleBluetooth" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    try {
                        val bluetoothAdapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter()
                        if (bluetoothAdapter != null) {
                            if (enable) bluetoothAdapter.enable() else bluetoothAdapter.disable()
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("BT_ERROR", e.message, null)
                    }
                }

                "isBluetoothEnabled" -> {
                    try {
                        val bluetoothAdapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter()
                        result.success(bluetoothAdapter?.isEnabled == true)
                    } catch (e: Exception) {
                        result.error("BT_STATE_ERROR", e.message, null)
                    }
                }

                "isHotspotEnabled" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        val method = wifiManager.javaClass.getDeclaredMethod("getWifiApState")
                        val state = method.invoke(wifiManager) as Int
                        // 13 is WIFI_AP_STATE_ENABLED
                        result.success(state == 13)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "getInstalledApps" -> {
                    try {
                        val pm = packageManager
                        val apps = pm.getInstalledApplications(android.content.pm.PackageManager.GET_META_DATA)
                        val appList = mutableListOf<Map<String, Any>>()

                        for (app in apps) {
                            val launchIntent = pm.getLaunchIntentForPackage(app.packageName)
                            if (launchIntent != null) {
                                val label = app.loadLabel(pm).toString()
                                val apkPath = app.sourceDir
                                val size = java.io.File(apkPath).length()
                                
                                val appMap = mapOf(
                                    "name" to label,
                                    "packageName" to app.packageName,
                                    "apkPath" to apkPath,
                                    "size" to size
                                )
                                appList.add(appMap)
                            }
                        }
                        result.success(appList)
                    } catch (e: Exception) {
                        result.error("APP_LIST_ERROR", e.message, null)
                    }
                }

                "checkAllFilesPermission" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        result.success(android.os.Environment.isExternalStorageManager())
                    } else {
                        result.success(true)
                    }
                }

                "openAllFilesPermission" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                            intent.data = android.net.Uri.parse("package:$packageName")
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        }
                    } else {
                        result.success(true)
                    }
                }

                "getMediaAssets" -> {
                    val type = call.argument<String>("type") ?: "image"
                    try {
                        val mediaList = mutableListOf<Map<String, Any>>()
                        val projection = arrayOf<String>(
                            MediaStore.MediaColumns.DISPLAY_NAME,
                            MediaStore.MediaColumns.DATA,
                            MediaStore.MediaColumns.SIZE,
                            MediaStore.MediaColumns.MIME_TYPE,
                            MediaStore.MediaColumns.DATE_ADDED
                        )
                        
                        val uri = if (type == "video") {
                            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                        } else {
                            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                        }

                        val sortOrder = "${MediaStore.MediaColumns.DATE_ADDED} DESC"

                        contentResolver.query(uri, projection, null, null, sortOrder)?.use { cursor ->
                            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                            val dataCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                            val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)

                            var count = 0
                            while (cursor.moveToNext() && count < 500) {
                                val path = cursor.getString(dataCol)
                                if (path != null && java.io.File(path).exists()) {
                                    mediaList.add(mapOf(
                                        "name" to (cursor.getString(nameCol) ?: "Unknown"),
                                        "path" to path,
                                        "size" to cursor.getLong(sizeCol),
                                        "mimeType" to (cursor.getString(mimeCol) ?: "")
                                    ))
                                    count++
                                }
                            }
                        }
                        result.success(mediaList)
                    } catch (e: Exception) {
                        result.error("MEDIA_SCAN_ERROR", e.message, null)
                    }
                }

                "openHotspotSettings" -> {
                    try {
                        val intent = Intent()
                        intent.action = "android.settings.TETHER_SETTINGS"
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val intent = Intent(Settings.ACTION_WIRELESS_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.success(false)
                        }
                    }
                }

                "openBluetoothSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BLUETOOTH_STATE_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    bluetoothReceiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                                val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                                val isEnabled = (state == BluetoothAdapter.STATE_ON)
                                events?.success(isEnabled)
                            }
                        }
                    }
                    val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
                    registerReceiver(bluetoothReceiver, filter)
                    
                    val adapter = BluetoothAdapter.getDefaultAdapter()
                    events?.success(adapter?.isEnabled == true)
                }

                override fun onCancel(arguments: Any?) {
                    unregisterReceiver(bluetoothReceiver)
                    bluetoothReceiver = null
                }
            }
        )
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable) {
            return drawable.bitmap
        }
        val bitmap = Bitmap.createBitmap(
            drawable.intrinsicWidth.coerceAtLeast(1),
            drawable.intrinsicHeight.coerceAtLeast(1),
            Bitmap.Config.ARGB_8888
        )
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }
}
