package com.messapp.dev

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    /**
     * Lets Dart ask the platform which timezone the device is set to.
     *
     * The `timezone` package defaults `tz.local` to UTC. Without this, a
     * reminder set for 21:00 is scheduled at 21:00 UTC, which is hours away
     * from when the user asked for it.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getTimeZoneId") {
                    result.success(TimeZone.getDefault().getID())
                } else {
                    result.notImplemented()
                }
            }
    }

    private companion object {
        // Namespaced per app, so the sandbox and the real app register
        // separate channels.
        const val CHANNEL = "messapp/dev/timezone"
    }
}