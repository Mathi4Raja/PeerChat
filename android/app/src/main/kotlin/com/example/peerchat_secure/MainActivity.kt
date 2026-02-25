package com.example.peerchat_secure

import android.content.Context
import android.content.Intent
import android.os.BatteryManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val DEVICE_STATUS_CHANNEL = "peerchat_secure/device_status"
    }

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

                "openLocationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
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
    }
}
