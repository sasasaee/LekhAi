package com.example.lekhai

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.lekhai/kiosk"

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        io.flutter.plugin.common.MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startKioskMode") {
                try {
                    startLockTask()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("KIOSK_ERROR", "Failed to enter kiosk mode: ${e.message}", null)
                }
            } else if (call.method == "stopKioskMode") {
                try {
                    stopLockTask()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("KIOSK_ERROR", "Failed to exit kiosk mode: ${e.message}", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
