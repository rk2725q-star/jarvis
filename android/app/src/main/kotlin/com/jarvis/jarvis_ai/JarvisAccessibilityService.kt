package com.jarvis.jarvis_ai

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Rect
import android.net.Uri
import android.os.Bundle
import android.util.Base64
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.util.Log
import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap

class JarvisAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "JarvisV3"
        var instance: JarvisAccessibilityService? = null
            private set
        
        // ── OpenClaw-Grade Performance Caches ─────────────────────────────
        val packageCache = ConcurrentHashMap<String, String>()
        val refCache = ConcurrentHashMap<String, AccessibilityNodeInfo>()
        var lastScreenSignature: String = ""
        var onNotification: ((String) -> Unit)? = null
    }

    private val recentNotifications = mutableListOf<String>()
    private var lastRootNodes: List<AccessibilityNodeInfo> = emptyList()
    private var lastSnapshotTime = 0L

    fun getRecentNotifications(): String {
        synchronized(recentNotifications) {
            if (recentNotifications.isEmpty()) return "No recent notifications"
            return recentNotifications.joinToString("\n")
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        try {
            val info = serviceInfo
            info.flags = info.flags or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            serviceInfo = info
        } catch (e: Exception) {
            // Ignore
        }
        warmPackageCache()
        Log.d(TAG, "V3 connected, ${packageCache.size} apps cached")
    }

    override fun onDestroy() {
        refCache.values.forEach { runCatching { it.recycle() } }
        refCache.clear()
        instance = null
        super.onDestroy()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        refCache.values.forEach { runCatching { it.recycle() } }
        refCache.clear()
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: ""
        
        if (pkg == "com.google.android.apps.nbu.paisa.user") {
            Log.w(TAG, "GPay detected, disabling accessibility service to prevent security warnings.")
            disableSelf()
            return
        }

        if (event?.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) {
            val text = event.text.joinToString(" ").trim()
            if (text.isNotEmpty()) {
                val formatted = "[$pkg] $text"
                synchronized(recentNotifications) {
                    recentNotifications.add(0, formatted)
                    if (recentNotifications.size > 20) {
                        recentNotifications.removeAt(recentNotifications.size - 1)
                    }
                }
            }
            onNotification?.invoke("[$pkg] $text")
        }
    }

    override fun onInterrupt() {}

    // ═════════════════════════════════════════════════════════════════════
    //  WARM CACHE — Pre-load all packages at startup
    // ═════════════════════════════════════════════════════════════════════
    private fun warmPackageCache() {
        try {
            val pm = packageManager
            val mainIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            pm.queryIntentActivities(mainIntent, 0).forEach { resolveInfo ->
                val label = resolveInfo.loadLabel(pm).toString()
                val pkg = resolveInfo.activityInfo.packageName
                packageCache[label.lowercase()] = pkg
                label.split(" ").forEach { word ->
                    if (word.length > 3) packageCache[word.lowercase()] = pkg
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error warming package cache: ${e.message}")
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  INCREMENTAL SNAPSHOT — OpenClaw-style diff
    //  Returns only CHANGED nodes, not full tree
    // ═════════════════════════════════════════════════════════════════════
    fun takeIncrementalSnapshot(): String {
        val currentTime = System.currentTimeMillis()
        val roots = getAllRoots()
        
        // Fast path: if same window count, do diff
        if (roots.size == lastRootNodes.size) {
            val diff = computeDiff(roots)
            roots.forEach { it.recycle() }
            lastSnapshotTime = currentTime
            return diff
        }
        
        // Full snapshot fallback
        return takeFullSnapshot(roots).also {
            roots.forEach { it.recycle() }
            lastSnapshotTime = currentTime
        }
    }

    fun takeFullSnapshot(roots: List<AccessibilityNodeInfo>? = null): String {
        refCache.values.forEach { runCatching { it.recycle() } }
        refCache.clear()
        val sb = StringBuilder()
        var index = 1
        val allRoots = roots ?: getAllRoots()

        for (root in allRoots) {
            index = collectNodesFast(root, sb, index)
            if (roots == null) {
                root.recycle()
            }
        }

        val result = sb.toString()
        lastScreenSignature = result
        return if (result.isEmpty()) "EMPTY" else result
    }

    fun takeRefSnapshot(): String {
        return takeFullSnapshot()
    }

    private fun getAllRoots(): List<AccessibilityNodeInfo> {
        val roots = windows?.mapNotNull { it.root } ?: emptyList()
        if (roots.isNotEmpty()) return roots
        return listOfNotNull(rootInActiveWindow)
    }

    private fun getActiveRootNode(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow
        if (root != null) return root
        try {
            val windows = windows
            if (windows != null && windows.isNotEmpty()) {
                for (window in windows) {
                    if (window.isActive) {
                        val r = window.root
                        if (r != null) return r
                    }
                }
                for (window in windows) {
                    val r = window.root
                    if (r != null) return r
                }
            }
        } catch (e: Exception) {
            // Ignore
        }
        return null
    }

    // ── Fast Node Collection ───────────────────────────────────────────
    private fun collectNodesFast(
        node: AccessibilityNodeInfo?,
        sb: StringBuilder,
        startIndex: Int
    ): Int {
        if (node == null) return startIndex
        var index = startIndex

        // Ultra-fast filter: visible AND (actionable OR has text)
        val isVisible = node.isVisibleToUser
        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        val visible = bounds.width() > 0 && bounds.height() > 0

        if (isVisible && visible && 
            (node.isClickable || node.isEditable || node.isScrollable || node.isCheckable ||
             !node.text.isNullOrEmpty() || !node.contentDescription.isNullOrEmpty())) {
            
            val ref = "@e$index"
            try {
                refCache[ref] = AccessibilityNodeInfo.obtain(node)
                index++
            } catch (_: Exception) {}

            val text = node.text?.toString() ?: ""
            val desc = node.contentDescription?.toString() ?: ""
            val pkg = node.packageName?.toString() ?: "sys"
            val cls = node.className?.toString()?.substringAfterLast('.') ?: ""
            
            // Compact format: @e1[pkg/cls]"text"{actions}
            sb.append("$ref[$pkg/$cls]")
            if (text.isNotEmpty()) sb.append("\"$text\"")
            if (desc.isNotEmpty() && desc != text) sb.append("($desc)")
            sb.append("{")
            if (node.isClickable) sb.append("c")
            if (node.isEditable) sb.append("e")
            if (node.isScrollable) sb.append("s")
            if (node.isCheckable) sb.append("ch")
            sb.append("}\n")
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            index = collectNodesFast(child, sb, index)
        }
        return index
    }

    // ── Diff Engine ──────────────────────────────────────────────────────
    private fun computeDiff(newRoots: List<AccessibilityNodeInfo>): String {
        val sb = StringBuilder()
        val currentSnap = takeFullSnapshot(newRoots)
        val oldLines = lastScreenSignature.split("\n").toSet()
        val newLines = currentSnap.split("\n")
        for (line in newLines) {
            if (line.isNotEmpty() && !oldLines.contains(line)) {
                sb.append(line).append("\n")
            }
        }
        lastScreenSignature = currentSnap
        return sb.toString()
    }

    // ═════════════════════════════════════════════════════════════════════
    //  UNIVERSAL ACTIONS — Zero hardcoding
    // ═════════════════════════════════════════════════════════════════════

    fun clickRef(ref: String): String {
        val node = refCache[ref] ?: return "Error: ref $ref not found."
        val refreshed = node.refresh()
        if (!refreshed) return "Error: node $ref stale."

        return if (node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
            "Clicked $ref"
        } else {
            val parent = node.parent
            if (parent?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true) {
                "Clicked parent of $ref"
            } else {
                val b = Rect()
                node.getBoundsInScreen(b)
                val cx = b.centerX()
                val cy = b.centerY()
                val gestureResult = performTap(cx, cy)
                if (gestureResult == "OK") {
                    "Clicked $ref via gesture fallback @($cx,$cy)"
                } else {
                    "Click failed for $ref"
                }
            }
        }
    }

    fun typeIntoRef(ref: String, text: String, clearFirst: Boolean = false): String {
        val node = refCache[ref] ?: return "Error: ref $ref not found."
        node.refresh()

        node.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS)
        node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)

        if (clearFirst) {
            val selectAllArgs = Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, 0)
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, node.text?.length ?: 0)
            }
            node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selectAllArgs)
        }

        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return if (node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) {
            "Typed into $ref: \"$text\""
        } else {
            val pasteRes = pasteViaClipboard(node, text)
            if (pasteRes.contains("clipboard")) {
                pasteRes
            } else {
                val b = Rect()
                node.getBoundsInScreen(b)
                val cx = b.centerX()
                val cy = b.centerY()
                val tapRes = performTap(cx, cy)
                if (tapRes == "OK") {
                    Thread.sleep(300)
                    val typeRes = typeText(text)
                    if (typeRes == "OK") {
                        "Typed into $ref via gesture + type fallback"
                    } else {
                        "Type failed for $ref"
                    }
                } else {
                    "Type failed for $ref"
                }
            }
        }
    }

    private fun pasteViaClipboard(node: AccessibilityNodeInfo, text: String): String {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("jarvis", text))
        return if (node.performAction(AccessibilityNodeInfo.ACTION_PASTE)) {
            "Pasted via clipboard: \"$text\""
        } else {
            "Clipboard paste failed"
        }
    }

    fun scrollRef(ref: String, direction: String): String {
        val node = refCache[ref] ?: return "Error: ref not found"
        val action = if (direction.lowercase() == "up") {
            AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        } else {
            AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
        }
        return if (node.performAction(action)) "Scrolled $ref $direction" else "Scroll failed"
    }

    fun findRefByText(text: String): String {
        val q = text.lowercase()
        return refCache.entries.firstOrNull { (_, node) ->
            val nodeText = node.text?.toString()?.lowercase() ?: ""
            val nodeDesc = node.contentDescription?.toString()?.lowercase() ?: ""
            (nodeText.contains(q) || nodeDesc.contains(q)) && node.isVisibleToUser
        }?.key ?: ""
    }

    fun getRefCenter(ref: String): String {
        val node = refCache[ref] ?: return ""
        val b = Rect()
        node.getBoundsInScreen(b)
        return "{\"cx\":${b.centerX()},\"cy\":${b.centerY()}," +
               "\"left\":${b.left},\"top\":${b.top}," +
               "\"right\":${b.right},\"bottom\":${b.bottom}}"
    }

    // ─────────────────────────────────────────────
    // OBSERVE: Full Accessibility Tree (legacy text mode)
    // ─────────────────────────────────────────────
    fun getScreenContext(): String {
        val root = getActiveRootNode() ?: return "Screen: Empty (No Active Window)"
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
    // ─────────────────────────────────────────────
    fun takeScreenshot(callback: (String?) -> Unit) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.R) {
            callback(null)
            return
        }
        try {
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
    fun performTap(x: Int, y: Int): String {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        val result = dispatchGesture(gesture, null, null)
        return if (result) "OK" else "ERROR"
    }

    fun performLongPress(x: Int, y: Int): String {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 1500))
            .build()
        val result = dispatchGesture(gesture, null, null)
        return if (result) "OK" else "ERROR"
    }

    fun performDoubleTap(x: Int, y: Int): String {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val first = GestureDescription.StrokeDescription(path, 0, 50)
        val second = GestureDescription.StrokeDescription(path, 200, 50)
        val gesture = GestureDescription.Builder()
            .addStroke(first)
            .addStroke(second)
            .build()
        val result = dispatchGesture(gesture, null, null)
        return if (result) "OK" else "ERROR"
    }

    // ─────────────────────────────────────────────
    // ACT: Swipe / Scroll
    // ─────────────────────────────────────────────
    fun performSwipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Long = 300): String {
        val path = Path().apply {
            moveTo(x1.toFloat(), y1.toFloat())
            lineTo(x2.toFloat(), y2.toFloat())
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        val result = dispatchGesture(gesture, null, null)
        return if (result) "OK" else "ERROR"
    }

    fun performScrollDown(): String {
        val root = getActiveRootNode() ?: return "ERROR: no root"
        val scrollable = findScrollable(root)
        if (scrollable != null) {
            val res = scrollable.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
            scrollable.recycle()
            return if (res) "OK" else "ERROR"
        }
        val display = resources.displayMetrics
        val cx = display.widthPixels / 2
        return performSwipe(cx, (display.heightPixels * 0.75).toInt(), cx, (display.heightPixels * 0.25).toInt())
    }

    fun performScrollUp(): String {
        val root = getActiveRootNode() ?: return "ERROR: no root"
        val scrollable = findScrollable(root)
        if (scrollable != null) {
            val res = scrollable.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
            scrollable.recycle()
            return if (res) "OK" else "ERROR"
        }
        val display = resources.displayMetrics
        val cx = display.widthPixels / 2
        return performSwipe(cx, (display.heightPixels * 0.25).toInt(), cx, (display.heightPixels * 0.75).toInt())
    }

    private fun findScrollable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isScrollable) return AccessibilityNodeInfo.obtain(node)
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findScrollable(child)
            child.recycle()
            if (found != null) return found
        }
        return null
    }

    // ─────────────────────────────────────────────
    // ACT: Type Text / Clear / Paste
    // ─────────────────────────────────────────────
    fun typeText(text: String): String {
        val root = getActiveRootNode() ?: return "ERROR: no root"
        val focused = findEditableNode(root)
        val res = if (focused != null) {
            val arguments = Bundle()
            arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            var success = focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
            if (!success) {
                val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("jarvis", text))
                success = focused.performAction(AccessibilityNodeInfo.ACTION_PASTE)
            }
            focused.recycle()
            success
        } else {
            false
        }
        root.recycle()
        return if (res) "OK" else "ERROR"
    }

    fun clearText(): String {
        val root = getActiveRootNode() ?: return "ERROR: no root"
        val focused = findEditableNode(root)
        val res = if (focused != null) {
            focused.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            val args = Bundle()
            args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "")
            val success = focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            focused.recycle()
            success
        } else {
            false
        }
        root.recycle()
        return if (res) "OK" else "ERROR"
    }

    fun pasteFromClipboard(): String {
        val root = getActiveRootNode() ?: return "ERROR: no root"
        val focused = findEditableNode(root)
        val res = if (focused != null) {
            val success = focused.performAction(AccessibilityNodeInfo.ACTION_PASTE)
            focused.recycle()
            success
        } else {
            false
        }
        root.recycle()
        return if (res) "OK" else "ERROR"
    }

    private fun findEditableNode(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isEditable || node.isFocused && (node.className == "android.widget.EditText")) {
            return AccessibilityNodeInfo.obtain(node)
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findEditableNode(child)
            child.recycle()
            if (found != null) return found
        }
        return null
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  clickNodeByText — Deep tree search with PARTIAL match
    // ══════════════════════════════════════════════════════════════════════════
    fun clickNodeByText(text: String): String {
        val root = rootInActiveWindow ?: return "Error: No active window"
        val node = findNodeByTextDeep(root, text)
        root.recycle()

        return if (node != null) {
            val clicked = node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                || node.parent?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true
            if (clicked) "Clicked: \"$text\"" else "Found but click failed: \"$text\""
        } else {
            "Element not found: \"$text\""
        }
    }

    private fun findNodeByTextDeep(node: AccessibilityNodeInfo?, query: String): AccessibilityNodeInfo? {
        if (node == null) return null
        val q = query.lowercase()
        val nodeText = node.text?.toString()?.lowercase() ?: ""
        val nodeDesc = node.contentDescription?.toString()?.lowercase() ?: ""

        if ((nodeText.contains(q) || nodeDesc.contains(q)) && node.isVisibleToUser) {
            return node
        }
        for (i in 0 until node.childCount) {
            val result = findNodeByTextDeep(node.getChild(i), query)
            if (result != null) return result
        }
        return null
    }

    fun focusNodeByText(text: String): String {
        val root = getActiveRootNode() ?: return "ERROR: no root"
        val nodes = root.findAccessibilityNodeInfosByText(text)
        val res = if (nodes.isNotEmpty()) {
            val node = nodes[0]
            val success = node.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS)
            nodes.forEach { it.recycle() }
            success
        } else {
            false
        }
        root.recycle()
        return if (res) "OK" else "ERROR"
    }

    // ─────────────────────────────────────────────
    // ACT: Global System Actions
    // ─────────────────────────────────────────────
    fun pressBack(): String {
        val res = performGlobalAction(GLOBAL_ACTION_BACK)
        return if (res) "OK" else "ERROR"
    }
    fun pressHome(): String {
        val res = performGlobalAction(GLOBAL_ACTION_HOME)
        return if (res) "OK" else "ERROR"
    }
    fun pressRecents(): String {
        val res = performGlobalAction(GLOBAL_ACTION_RECENTS)
        return if (res) "OK" else "ERROR"
    }
    fun pressNotifications(): String {
        val res = performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
        return if (res) "OK" else "ERROR"
    }
    fun pressQuickSettings(): String {
        val res = performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)
        return if (res) "OK" else "ERROR"
    }

    fun lockScreen(): String {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            val res = performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
            return if (res) "OK" else "ERROR"
        }
        return "ERROR: Requires Android 9+"
    }

    fun openPowerDialog(): String {
        val res = performGlobalAction(GLOBAL_ACTION_POWER_DIALOG)
        return if (res) "OK" else "ERROR"
    }

    fun directWhatsappAndSend(number: String, text: String): String {
        return try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("https://api.whatsapp.com/send?phone=$number&text=${Uri.encode(text)}")
                setPackage("com.whatsapp")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            "Opened WhatsApp chat for $number"
        } catch (e: Exception) {
            "ERROR: WhatsApp not installed or failed to open: ${e.message}"
        }
    }

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
    fun launchApp(packageName: String): String {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return "ERROR"
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return "OK"
    }

    // ─────────────────────────────────────────────
    // ACT: Open URL / Deep Link
    // ─────────────────────────────────────────────
    fun openUrl(url: String): String {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            "OK"
        } catch (e: Exception) {
            "ERROR"
        }
    }

    // ─────────────────────────────────────────────
    // ACT: Dismiss ALL Notifications
    // ─────────────────────────────────────────────
    fun dismissAllNotifications(): String {
        val res = performGlobalAction(GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE)
        return if (res) "OK" else "ERROR"
    }

    // HELPER: Get package name of active window
    // ─────────────────────────────────────────────
    fun getActivePackage(): String {
        val root = getActiveRootNode()
        val pkg = root?.packageName?.toString() ?: ""
        root?.recycle()
        return pkg
    }

    // ─────────────────────────────────────────────
    // ACT: Direct System Controls (Torch, Settings, Call, SMS)
    // ─────────────────────────────────────────────
    fun toggleTorch(state: String): String {
        return try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as android.hardware.camera2.CameraManager
            val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                val chars = cameraManager.getCameraCharacteristics(id)
                chars.get(android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
            if (cameraId != null) {
                val isOn = state.equals("on", ignoreCase = true)
                cameraManager.setTorchMode(cameraId, isOn)
                "Torch turned ${if (isOn) "ON" else "OFF"}"
            } else {
                "ERROR: No flashlight available on this device"
            }
        } catch (e: Exception) {
            "ERROR: Failed to toggle torch: ${e.message}"
        }
    }

    fun openSystemSetting(name: String): String {
        return try {
            val action = when (name.lowercase()) {
                "wifi", "wi-fi" -> android.provider.Settings.ACTION_WIFI_SETTINGS
                "bluetooth" -> android.provider.Settings.ACTION_BLUETOOTH_SETTINGS
                "display" -> android.provider.Settings.ACTION_DISPLAY_SETTINGS
                "location" -> android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS
                "date", "time" -> android.provider.Settings.ACTION_DATE_SETTINGS
                "airplane" -> android.provider.Settings.ACTION_AIRPLANE_MODE_SETTINGS
                else -> android.provider.Settings.ACTION_SETTINGS
            }
            val intent = Intent(action).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            "Opened $name settings"
        } catch (e: Exception) {
            "ERROR: Failed to open $name settings: ${e.message}"
        }
    }

    fun openSystemSettingByAction(action: String): String {
        return try {
            val intent = Intent(action).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            "Opened settings for action $action"
        } catch (e: Exception) {
            "ERROR: Failed to open setting by action $action: ${e.message}"
        }
    }

    fun directCall(number: String): String {
        return try {
            val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$number")).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            "Dialed phone call to $number"
        } catch (e: Exception) {
            try {
                val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
                "Opened dialer for $number"
            } catch (e2: Exception) {
                "ERROR: Failed to make call: ${e2.message}"
            }
        }
    }

    fun directSms(number: String, body: String): String {
        return try {
            val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$number")).apply {
                putExtra("sms_body", body)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            "Opened SMS composer to $number"
        } catch (e: Exception) {
            "ERROR: Failed to open SMS: ${e.message}"
        }
    }

    // ─────────────────────────────────────────────
    // ACT: Foreground Service Control
    // ─────────────────────────────────────────────
    private val FOREGROUND_NOTIFICATION_ID = 9912

    fun startForegroundMode(taskPrompt: String) {
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val channelId = "agentica_task_channel"
                val channelName = "JARVIS Agentica Tasks"
                val chan = NotificationChannel(
                    channelId,
                    channelName,
                    NotificationManager.IMPORTANCE_LOW
                )
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.createNotificationChannel(chan)

                val intent = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                val pendingIntent = PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE
                )

                val notification = Notification.Builder(this, channelId)
                    .setContentTitle("JARVIS Agentica")
                    .setContentText("Executing task: $taskPrompt")
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentIntent(pendingIntent)
                    .setOngoing(true)
                    .build()

                startForeground(FOREGROUND_NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Ignore failure to display notification
        }
    }

    fun stopForegroundMode() {
        try {
            stopForeground(true)
        } catch (e: Exception) {
            // Ignore
        }
    }
}
