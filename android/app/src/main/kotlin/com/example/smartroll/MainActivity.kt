package com.example.smartroll

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.provider.Settings 

class MainActivity : FlutterActivity(){
    private val DEV_MODE_CHANNEL = "com.smartroll.checks/dev_mode" // Must match Dart side

     override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
         super.configureFlutterEngine(flutterEngine)
         MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEV_MODE_CHANNEL).setMethodCallHandler {
             call, result ->
             if (call.method == "isDeveloperModeEnabled") {
                 val isEnabled = isDeveloperModeEnabled()
                 result.success(isEnabled)
             } else {
                 result.notImplemented()
             }
         }
     }

     // Function to check Android Developer Options status
     private fun isDeveloperModeEnabled(): Boolean {
         return try {
             // Settings.Global.DEVELOPMENT_SETTINGS_ENABLED is the key
             // The '0' is the default value if the setting is not found
             Settings.Global.getInt(contentResolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) == 1
         } catch (e: Exception) {
             // Handle potential exceptions (e.g., SecurityException on some devices)
             println("Error checking developer mode setting: ${e.message}")
             false // Assume disabled if check fails
         }
     }
}
