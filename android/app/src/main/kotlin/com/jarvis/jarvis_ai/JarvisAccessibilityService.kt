package com.jarvis.jarvis_ai

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Rect
import android.net.Uri
import android.os.Bundle
import android.util.Base64
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.io.ByteArrayOutputStream

class JarvisAccessibilityService : AccessibilityService() {

    companion object {
        var instance: JarvisAccessibilityService? = null
            private set

        // Notification relay callback — set from MainActivity
        var onNotification: ((String) -> Unit)? = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) {
            val text = event.text.joinToString(" ")
            val pkg = event.packageName?.toString() ?: ""
            onNotification?.invoke("[$pkg] $text")
        }
    }

    override fun onInterrupt() {}

    // ─────────────────────────────────────────────
    // OBSERVE: Full Accessibility Tree
    // ─────────────────────────────────────────────
    fun getScreenContext(): String {
        val root = rootInActiveWindow ?: return "Screen: Empty (No Active Window)"
        val sb = StringBuilder()
        traverseNodes(root, sb, 0)
        return sb.toString()
    }

    private fun traverseNodes(node: AccessibilityNodeInfo?, sb: StringBuilder, depth: Int) {
        if (node == null || depth > 25) return
        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        val text = node.text?.toString() ?: node.contentDescription?.toString() ?: ""
        val id = node.viewIdResourceName?.split("/")?.lastOrNull() ?: ""
        val cls = node.className?.toString()?.split(".")?.lastOrNull() ?: ""
        val clickable = node.isClickable
        val editable = node.isEditable
        val scrollable = node.isScrollable
        val checked = if (node.isCheckable) "(checked=${node.isChecked})" else ""
        if (text.isNotEmpty() || id.isNotEmpty() || clickable || editable || scrollable) {
            sb.append("${"  ".repeat(depth)}[${bounds.centerX()},${bounds.centerY()}] ")
            if (id.isNotEmpty()) sb.append("ID:$id ")
            if (cls.isNotEmpty()) sb.append("CLS:$cls ")
            if (text.isNotEmpty()) sb.append("TEXT:\"$text\" ")
            if (clickable) sb.append("(clickable) ")
            if (editable) sb.append("(editable) ")
            if (scrollable) sb.append("(scrollable) ")
            if (checked.isNotEmpty()) sb.append(checked)
            sb.append("\n")
        }
        for (i in 0 until node.childCount) traverseNodes(node.getChild(i), sb, depth + 1)
    }

    // ─────────────────────────────────────────────
    // OBSERVE: Screenshot as Base64 (Android 11+ only)
    // Uses reflection to avoid compile issues with ScreenshotResult API
    // ─────────────────────────────────────────────
    fun takeScreenshot(callback: (String?) -> Unit) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.R) {
            callback(null)
            return
        }
        try {
            // takeScreenshot(int displayId, Executor executor, TakeScreenshotCallback callback)
            val method = AccessibilityService::class.java.getMethod(
                "takeScreenshot",
                Int::class.java,
                java.util.concurrent.Executor::class.java,
                Class.forName("android.accessibilityservice.AccessibilityService\$TakeScreenshotCallback")
            )

            val callbackClass = Class.forName(
                "android.accessibilityservice.AccessibilityService\$TakeScreenshotCallback"
            )
            val proxy = java.lang.reflect.Proxy.newProxyInstance(
                callbackClass.classLoader,
                arrayOf(callbackClass)
            ) { _, proxyMethod, args ->
                when (proxyMethod.name) {
                    "onSuccess" -> {
                        try {
                            val result = args[0]
                            val bmpMethod = result!!.javaClass.getMethod("getHardwareBitmap")
                            val hwBmp = bmpMethod.invoke(result) as? Bitmap
                            val softBmp = hwBmp?.copy(Bitmap.Config.ARGB_8888, false)
                            val out = ByteArrayOutputStream()
                            softBmp?.compress(Bitmap.CompressFormat.JPEG, 65, out)
                            val b64 = Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
                            softBmp?.recycle()
                            // Call release() to free the ScreenshotResult
                            runCatching { result.javaClass.getMethod("release").invoke(result) }
                            callback(b64)
                        } catch (e: Exception) {
                            callback(null)
                        }
                    }
                    "onFailure" -> callback(null)
                }
                null
            }

            method.invoke(this, android.view.Display.DEFAULT_DISPLAY, mainExecutor, proxy)
        } catch (e: Exception) {
            callback(null)
        }
    }

    // ─────────────────────────────────────────────
    // ACT: Tap / Long-press / Double-tap
    // ─────────────────────────────────────────────
    fun performTap(x: Int, y: Int): Boolean {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    fun performLongPress(x: Int, y: Int): Boolean {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 1500))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    fun performDoubleTap(x: Int, y: Int): Boolean {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val first = GestureDescription.StrokeDescription(path, 0, 50)
        val second = GestureDescription.StrokeDescription(path, 200, 50)
        val gesture = GestureDescription.Builder()
            .addStroke(first)
            .addStroke(second)
            .build()
        return dispatchGesture(gesture, null, null)
    }

    // ─────────────────────────────────────────────
    // ACT: Swipe / Scroll
    // ─────────────────────────────────────────────
    fun performSwipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Long = 300): Boolean {
        val path = Path().apply {
            moveTo(x1.toFloat(), y1.toFloat())
            lineTo(x2.toFloat(), y2.toFloat())
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    fun performScrollDown(): Boolean {
        val root = rootInActiveWindow ?: return false
        // Try scrollable node first
        val scrollable = findScrollable(root)
        if (scrollable != null) {
            return scrollable.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
        }
        // Fall back to swipe gesture
        val display = resources.displayMetrics
        val cx = display.widthPixels / 2
        return performSwipe(cx, (display.heightPixels * 0.75).toInt(), cx, (display.heightPixels * 0.25).toInt())
    }

    fun performScrollUp(): Boolean {
        val root = rootInActiveWindow ?: return false
        val scrollable = findScrollable(root)
        if (scrollable != null) {
            return scrollable.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
        }
        val display = resources.displayMetrics
        val cx = display.widthPixels / 2
        return performSwipe(cx, (display.heightPixels * 0.25).toInt(), cx, (display.heightPixels * 0.75).toInt())
    }

    private fun findScrollable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isScrollable) return node
        for (i in 0 until node.childCount) {
            val found = findScrollable(node.getChild(i) ?: continue)
            if (found != null) return found
        }
        return null
    }

    // ─────────────────────────────────────────────
    // ACT: Type Text / Clear / Paste
    // ─────────────────────────────────────────────
    fun typeText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val focused = findEditableNode(root)
        if (focused != null) {
            val arguments = Bundle()
            arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            return focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
        }
        return false
    }

    fun clearText(): Boolean {
        val root = rootInActiveWindow ?: return false
        val focused = findEditableNode(root)
        if (focused != null) {
            // Select all then delete
            focused.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            val args = Bundle()
            args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "")
            return focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        }
        return false
    }

    fun pasteFromClipboard(): Boolean {
        val root = rootInActiveWindow ?: return false
        val focused = findEditableNode(root)
        return focused?.performAction(AccessibilityNodeInfo.ACTION_PASTE) ?: false
    }

    private fun findEditableNode(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isEditable || node.isFocused && (node.className == "android.widget.EditText")) return node
        for (i in 0 until node.childCount) {
            val found = findEditableNode(node.getChild(i) ?: continue)
            if (found != null) return found
        }
        return null
    }

    // ─────────────────────────────────────────────
    // ACT: Find & Click node by text
    // ─────────────────────────────────────────────
    fun clickNodeByText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val nodes = root.findAccessibilityNodeInfosByText(text)
        for (node in nodes) {
            if (node.isClickable) {
                return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            }
            // Walk up to find clickable parent
            var parent = node.parent
            var depth = 0
            while (parent != null && depth < 5) {
                if (parent.isClickable) {
                    return parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                }
                parent = parent.parent
                depth++
            }
        }
        return false
    }

    fun focusNodeByText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val nodes = root.findAccessibilityNodeInfosByText(text)
        return nodes.firstOrNull()?.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS) ?: false
    }

    // ─────────────────────────────────────────────
    // ACT: Global System Actions
    // ─────────────────────────────────────────────
    fun pressBack(): Boolean = performGlobalAction(GLOBAL_ACTION_BACK)
    fun pressHome(): Boolean = performGlobalAction(GLOBAL_ACTION_HOME)
    fun pressRecents(): Boolean = performGlobalAction(GLOBAL_ACTION_RECENTS)
    fun pressNotifications(): Boolean = performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
    fun pressQuickSettings(): Boolean = performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)

    // ─────────────────────────────────────────────
    // ACT: Clipboard Read/Write
    // ─────────────────────────────────────────────
    fun readClipboard(): String {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        return cm.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
    }

    fun writeClipboard(text: String) {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("JARVIS", text))
    }

    // ─────────────────────────────────────────────
    // ACT: Launch App by Package Name
    // ─────────────────────────────────────────────
    fun launchApp(packageName: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return true
    }

    // ─────────────────────────────────────────────
    // ACT: Open URL / Deep Link
    // ─────────────────────────────────────────────
    fun openUrl(url: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    // ─────────────────────────────────────────────
    // ACT: Dismiss ALL Notifications
    // ─────────────────────────────────────────────
    fun dismissAllNotifications(): Boolean = performGlobalAction(GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE)

    // ─────────────────────────────────────────────
    // HELPER: Get package name of active window
    // ─────────────────────────────────────────────
    fun getActivePackage(): String {
        return rootInActiveWindow?.packageName?.toString() ?: ""
    }
}
