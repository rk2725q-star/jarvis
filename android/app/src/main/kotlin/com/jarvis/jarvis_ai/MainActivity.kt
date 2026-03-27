package com.jarvis.jarvis_ai

import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val ACCESSIBILITY_CHANNEL = "jarvis.ai.os/accessibility"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACCESSIBILITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                val service = JarvisAccessibilityService.instance

                when (call.method) {
                    // ── Status ─────────────────────────────────────
                    "isAccessibilityEnabled" -> {
                        result.success(isServiceEnabled(this, JarvisAccessibilityService::class.java))
                    }
                    "requestAccessibility" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "getActivePackage" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.getActivePackage())
                    }

                    // ── Observe ────────────────────────────────────
                    "getScreenContext" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.getScreenContext())
                    }
                    "takeScreenshot" -> {
                        if (service == null) {
                            result.error("NOT_CONNECTED", "Service not enabled", null)
                        } else {
                            service.takeScreenshot { b64 ->
                                if (b64 != null) result.success(b64)
                                else result.error("SCREENSHOT_FAILED", "Screenshot capture failed (requires Android 11+)", null)
                            }
                        }
                    }

                    // ── Tap Actions ────────────────────────────────
                    "performTap" -> {
                        val x = call.argument<Int>("x") ?: 0
                        val y = call.argument<Int>("y") ?: 0
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.performTap(x, y))
                    }
                    "performLongPress" -> {
                        val x = call.argument<Int>("x") ?: 0
                        val y = call.argument<Int>("y") ?: 0
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.performLongPress(x, y))
                    }
                    "performDoubleTap" -> {
                        val x = call.argument<Int>("x") ?: 0
                        val y = call.argument<Int>("y") ?: 0
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.performDoubleTap(x, y))
                    }
                    "clickNodeByText" -> {
                        val text = call.argument<String>("text") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.clickNodeByText(text))
                    }
                    "focusNodeByText" -> {
                        val text = call.argument<String>("text") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.focusNodeByText(text))
                    }

                    // ── Swipe / Scroll ─────────────────────────────
                    "performSwipe" -> {
                        val x1 = call.argument<Int>("x1") ?: 0
                        val y1 = call.argument<Int>("y1") ?: 0
                        val x2 = call.argument<Int>("x2") ?: 0
                        val y2 = call.argument<Int>("y2") ?: 0
                        val duration = call.argument<Int>("duration")?.toLong() ?: 300L
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.performSwipe(x1, y1, x2, y2, duration))
                    }
                    "scrollDown" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.performScrollDown())
                    }
                    "scrollUp" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.performScrollUp())
                    }

                    // ── Text Input ─────────────────────────────────
                    "typeText" -> {
                        val text = call.argument<String>("text") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.typeText(text))
                    }
                    "clearText" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.clearText())
                    }
                    "pasteFromClipboard" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.pasteFromClipboard())
                    }

                    // ── Clipboard ──────────────────────────────────
                    "readClipboard" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.readClipboard())
                    }
                    "writeClipboard" -> {
                        val text = call.argument<String>("text") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else { service.writeClipboard(text); result.success(true) }
                    }

                    // ── Navigation ─────────────────────────────────
                    "pressBack" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.pressBack())
                    }
                    "pressHome" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.pressHome())
                    }
                    "pressRecents" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.pressRecents())
                    }
                    "pressNotifications" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.pressNotifications())
                    }
                    "pressQuickSettings" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.pressQuickSettings())
                    }

                    // ── App Launch & URL ───────────────────────────
                    "launchApp" -> {
                        val packageName = call.argument<String>("packageName") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.launchApp(packageName))
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.openUrl(url))
                    }

                    // ── Notifications ──────────────────────────────
                    "dismissAllNotifications" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.dismissAllNotifications())
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun isServiceEnabled(context: Context, service: Class<*>): Boolean {
        val expected = "${context.packageName}/${service.name}"
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        while (splitter.hasNext()) {
            if (splitter.next().equals(expected, ignoreCase = true)) return true
        }
        return false
    }
}
