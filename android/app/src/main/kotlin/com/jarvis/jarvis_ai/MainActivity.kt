package com.jarvis.jarvis_ai

import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.media.audiofx.LoudnessEnhancer
import android.net.Uri
import android.os.Environment
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import android.hardware.display.DisplayManager
import android.view.WindowManager

class MainActivity : AudioServiceActivity() {
    private val ACCESSIBILITY_CHANNEL = "jarvis.ai.os/accessibility"
    private val FILE_OPEN_CHANNEL = "jarvis.ai.os/file_open"
    private val MEDIA_SCANNER_CHANNEL = "com.jarvis.jarvis_ai/media_scanner"
    private val SHORTCUT_CHANNEL = "jarvis.ai.os/shortcuts"
    private val AUDIO_CHANNEL = "jarvis.ai.os/audio"
    private val PLAYER_PLATFORM_CHANNEL = "com.aurora.player/platform"
    
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var originalBrightness: Float = -1f

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Audio boost channel — uses Android LoudnessEnhancer for real hardware-level gain
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setLoudnessGain" -> {
                        val gainMb = call.argument<Int>("gainMb") ?: 0
                        val specificSessionId = call.argument<Int>("sessionId") // optional — from just_audio
                        try {
                            val appliedSessions = mutableListOf<Int>()

                            // 1. If Flutter passed us the actual ExoPlayer session ID, prioritize that
                            if (specificSessionId != null && specificSessionId > 0) {
                                try {
                                    val le = LoudnessEnhancer(specificSessionId)
                                    if (gainMb > 0) {
                                        le.setTargetGain(gainMb)
                                        le.enabled = true
                                    } else {
                                        le.enabled = false
                                        le.release()
                                    }
                                    appliedSessions.add(specificSessionId)
                                } catch (_: Exception) { }
                            }

                            // 2. Also apply to common session IDs used by ExoPlayer / MediaPlayer
                            for (sessionId in 0..8) {
                                if (sessionId == specificSessionId) continue // already applied
                                try {
                                    val le = LoudnessEnhancer(sessionId)
                                    if (gainMb > 0) {
                                        le.setTargetGain(gainMb)
                                        le.enabled = true
                                    } else {
                                        le.enabled = false
                                        le.release()
                                    }
                                    appliedSessions.add(sessionId)
                                } catch (_: Exception) { }
                            }

                            // 3. Persist a reference on session 0 for lifecycle management
                            if (loudnessEnhancer == null) {
                                loudnessEnhancer = try { LoudnessEnhancer(0) } catch (_: Exception) { null }
                            }
                            loudnessEnhancer?.let {
                                if (gainMb > 0) {
                                    it.setTargetGain(gainMb)
                                    it.enabled = true
                                } else {
                                    it.enabled = false
                                }
                            }

                            result.success(appliedSessions)
                        } catch (e: Exception) {
                            result.error("AUDIO_ERROR", e.message, null)
                        }
                    }
                    "getAudioSessionId" -> {
                        // Return the current audio session ID (Android media framework)
                        try {
                            val am = getSystemService(android.media.AudioManager::class.java)
                            result.success(am?.generateAudioSessionId() ?: 0)
                        } catch (e: Exception) {
                            result.success(0)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLAYER_PLATFORM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setBrightness" -> {
                        val brightness = call.argument<Double>("brightness")?.toFloat() ?: 0.5f
                        setScreenBrightness(brightness)
                        result.success(null)
                    }
                    "resetBrightness" -> {
                        resetScreenBrightness()
                        result.success(null)
                    }
                    "checkHdrSupport" -> {
                        result.success(checkHdrCapabilities())
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACCESSIBILITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                val service = JarvisAccessibilityService.instance

                when (call.method) {
                    // ── Status ─────────────────────────────────────
                    "isAccessibilityEnabled" -> {
                        result.success(isServiceEnabled(this, JarvisAccessibilityService::class.java))
                    }
                    "getAccessibilityStatus" -> {
                        val isEnabled = isServiceEnabled(this, JarvisAccessibilityService::class.java)
                        val isRunning = JarvisAccessibilityService.instance != null
                        val status = mapOf(
                            "enabled" to isEnabled,
                            "running" to isRunning
                        )
                        result.success(status)
                    }
                    "requestAccessibility" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "startForegroundMode" -> {
                        val prompt = call.argument<String>("prompt") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else {
                            service.startForegroundMode(prompt)
                            result.success(true)
                        }
                    }
                    "stopForegroundMode" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else {
                            service.stopForegroundMode()
                            result.success(true)
                        }
                    }
                    "toggleTorch" -> {
                        val state = call.argument<String>("state") ?: "off"
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.toggleTorch(state))
                    }
                    "openSystemSetting" -> {
                        val name = call.argument<String>("name") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.openSystemSetting(name))
                    }
                    "directCall" -> {
                        val number = call.argument<String>("number") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.directCall(number))
                    }
                    "directSms" -> {
                        val number = call.argument<String>("number") ?: ""
                        val body = call.argument<String>("body") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.directSms(number, body))
                    }
                    "getActivePackage" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.getActivePackage())
                    }

                    // ── Observe ────────────────────────────────────
                    // OpenClaw-style snapshot — assigns @e1..@eN refs
                    "takeRefSnapshot" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else {
                            Thread {
                                val snap = service.takeRefSnapshot()
                                runOnUiThread { result.success(snap) }
                            }.start()
                        }
                    }
                    "takeIncrementalSnapshot" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else {
                            Thread {
                                val snap = service.takeIncrementalSnapshot()
                                runOnUiThread { result.success(snap) }
                            }.start()
                        }
                    }
                    "findRefByText" -> {
                        val text = call.argument<String>("text") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else {
                            Thread {
                                val ref = service.findRefByText(text)
                                runOnUiThread { result.success(ref) }
                            }.start()
                        }
                    }
                    "getRefCenter" -> {
                        val ref = call.argument<String>("ref") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.getRefCenter(ref))
                    }

                    // ── Ref-based Actions (accurate, no coordinate guessing) ──
                    "clickRef" -> {
                        val ref = call.argument<String>("ref") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.clickRef(ref))
                    }
                    "typeIntoRef" -> {
                        val ref = call.argument<String>("ref") ?: ""
                        val text = call.argument<String>("text") ?: ""
                        val clearFirst = call.argument<Boolean>("clearFirst") ?: true
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.typeIntoRef(ref, text, clearFirst))
                    }
                    "scrollRef" -> {
                        val ref = call.argument<String>("ref") ?: ""
                        val direction = call.argument<String>("direction") ?: "down"
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.scrollRef(ref, direction))
                    }

                    "getScreenContext" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else {
                            Thread {
                                val ctx = service.getScreenContext()
                                runOnUiThread { result.success(ctx) }
                            }.start()
                        }
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
                        else {
                            Thread {
                                val res = service.clickNodeByText(text)
                                runOnUiThread { result.success(res) }
                            }.start()
                        }
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
                    "lockScreen" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.lockScreen())
                    }
                    "openPowerDialog" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.openPowerDialog())
                    }
                    "directWhatsapp" -> {
                        val number = call.argument<String>("number") ?: ""
                        val text = call.argument<String>("text") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.directWhatsappAndSend(number, text))
                    }

                    "launchApp" -> {
                        val packageName = call.argument<String>("packageName") ?: call.argument<String>("package") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.launchApp(packageName))
                    }
                    "getAllPackages" -> {
                        val pm = packageManager
                        val mainIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                        val apps = pm.queryIntentActivities(mainIntent, 0)
                        val pkgMap = mutableMapOf<String, String>()
                        for (resolveInfo in apps) {
                            val label = resolveInfo.loadLabel(pm).toString()
                            val pkg = resolveInfo.activityInfo.packageName
                            pkgMap[label] = pkg
                        }
                        result.success(pkgMap)
                    }
                    "sendMessage" -> {
                        val number = call.argument<String>("number") ?: ""
                        val text = call.argument<String>("text") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.directSms(number, text))
                    }
                    "openSetting" -> {
                        val action = call.argument<String>("action") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.openSystemSettingByAction(action))
                    }
                    "launchAppByName" -> {
                        // Agentica: find and launch any app by display name (not package)
                        val name = call.argument<String>("name") ?: ""
                        val pm = packageManager
                        val apps = pm.getInstalledApplications(0)
                        val match = apps.firstOrNull {
                            pm.getApplicationLabel(it).toString().contains(name, ignoreCase = true)
                                    || it.packageName.contains(name, ignoreCase = true)
                        }
                        if (match != null) {
                            val intent = pm.getLaunchIntentForPackage(match.packageName)
                            if (intent != null) {
                                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                startActivity(intent)
                                result.success("Opened ${pm.getApplicationLabel(match)}")
                            } else result.error("NO_INTENT", "Cannot launch ${match.packageName}", null)
                        } else result.error("NOT_FOUND", "App '$name' not found", null)
                    }
                    "getInstalledApps" -> {
                        // Agentica: get all launchable app names
                        val pm = packageManager
                        val names = pm.getInstalledApplications(0)
                            .filter { pm.getLaunchIntentForPackage(it.packageName) != null }
                            .map { pm.getApplicationLabel(it).toString() }
                            .sorted()
                        result.success(names.joinToString(", "))
                    }
                    "searchContacts" -> {
                        // Agentica: search device contacts by name
                        val name = call.argument<String>("name") ?: ""
                        val contacts = mutableListOf<String>()
                        val cursor = contentResolver.query(
                            android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                            arrayOf(
                                android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                                android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER
                            ),
                            "${android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
                            arrayOf("%$name%"),
                            android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME
                        )
                        cursor?.use { c ->
                            while (c.moveToNext()) {
                                val n = c.getString(0) ?: continue
                                val num = c.getString(1) ?: continue
                                contacts.add("$n: $num")
                            }
                        }
                        result.success(
                            if (contacts.isEmpty()) "No contacts found for '$name'"
                            else contacts.take(5).joinToString("\n")
                        )
                    }

                    "getRecentNotifications" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.getRecentNotifications())
                    }

                    "openUrl" -> {
                        val url = call.argument<String>("url") ?: ""
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.openUrl(url))
                    }
                    "dismissAllNotifications" -> {
                        if (service == null) result.error("NOT_CONNECTED", "Service not enabled", null)
                        else result.success(service.dismissAllNotifications())
                    }

                    else -> result.notImplemented()
                }
            }

        // ── File Open Channel: called from Flutter to get the initial file path ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_OPEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFile" -> {
                        val path = resolveFilePath(intent)
                        result.success(path)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Media Scanner Channel: notifies Android gallery / file manager ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_SCANNER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanFile" -> {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            MediaScannerConnection.scanFile(
                                applicationContext,
                                arrayOf(path),
                                null
                            ) { _, _ -> result.success(true) }
                        } else {
                            result.error("INVALID", "No path provided", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Shortcut Channel: pin web app to home screen ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHORTCUT_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "pinShortcut") {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val shortcutManager = getSystemService(ShortcutManager::class.java)
                        if (shortcutManager != null && shortcutManager.isRequestPinShortcutSupported) {
                            val id = call.argument<String>("id") ?: "integration"
                            val label = call.argument<String>("label") ?: "App"
                            val url = call.argument<String>("url") ?: ""
                            
                            val intent = Intent(this, MainActivity::class.java).apply {
                                action = Intent.ACTION_MAIN
                                putExtra("integrationId", id)
                            }
                            
                            val pinShortcutInfo = ShortcutInfo.Builder(this, id)
                                .setShortLabel(label)
                                .setIntent(intent)
                                .setIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
                                .build()
                                
                            shortcutManager.requestPinShortcut(pinShortcutInfo, null)
                            result.success(true)
                        } else {
                            result.error("UNSUPPORTED", "Pin shortcut not supported", null)
                        }
                    } else {
                        result.error("UNSUPPORTED", "Requires Android 8+", null)
                    }
                } else if (call.method == "getInitialIntegrationId") {
                    result.success(intent.getStringExtra("integrationId"))
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Notify Flutter of the new file while app is already open
        val path = resolveFilePath(intent)
        if (path != null && flutterEngine != null) {
            MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, FILE_OPEN_CHANNEL)
                .invokeMethod("openFile", path)
        }
    }

    /** Resolve the real file path from a VIEW intent (handles both file:// and content:// URIs) */
    private fun resolveFilePath(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri: Uri = intent.data ?: return null
        return when (uri.scheme) {
            "file" -> uri.path
            "content" -> {
                // Copy content URI to a temp file Flutter can read
                try {
                    val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
                    val ext = mimeTypeToExt(mimeType)
                    val tmpFile = java.io.File(cacheDir, "jarvis_open_${System.currentTimeMillis()}$ext")
                    contentResolver.openInputStream(uri)?.use { input ->
                        tmpFile.outputStream().use { output -> input.copyTo(output) }
                    }
                    tmpFile.absolutePath
                } catch (e: Exception) {
                    null
                }
            }
            else -> null
        }
    }

    private fun mimeTypeToExt(mime: String): String = when {
        mime.contains("pdf") -> ".pdf"
        mime.contains("word") || mime.contains("msword") -> ".docx"
        mime.contains("powerpoint") || mime.contains("presentation") -> ".pptx"
        mime.contains("excel") || mime.contains("spreadsheet") -> ".xlsx"
        mime.contains("text/plain") -> ".txt"
        mime.contains("image/jpeg") -> ".jpg"
        mime.contains("image/png") -> ".png"
        mime.contains("image/") -> ".jpg"
        else -> ".bin"
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

    private fun setScreenBrightness(brightness: Float) {
        val win = window
        val layoutParams = win.attributes
        if (originalBrightness < 0) {
            originalBrightness = layoutParams.screenBrightness
        }
        layoutParams.screenBrightness = brightness.coerceIn(0f, 1f)
        win.attributes = layoutParams
    }

    private fun resetScreenBrightness() {
        val win = window
        val layoutParams = win.attributes
        layoutParams.screenBrightness = originalBrightness.coerceAtLeast(-1f)
        win.attributes = layoutParams
    }

    private fun checkHdrCapabilities(): Map<String, Any> {
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val display = displayManager.getDisplay(0) ?: return mapOf(
            "isHdrSupported" to false,
            "profiles" to listOf<String>(),
            "maxLuminance" to 0.0
        )

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val caps = display.hdrCapabilities
            val profiles = caps?.supportedHdrTypes?.map { type ->
                when (type) {
                    android.view.Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> "DolbyVision"
                    android.view.Display.HdrCapabilities.HDR_TYPE_HDR10 -> "HDR10"
                    android.view.Display.HdrCapabilities.HDR_TYPE_HLG -> "HLG"
                    android.view.Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS -> "HDR10+"
                    else -> "Unknown"
                }
            } ?: listOf()
            
            mapOf(
                "isHdrSupported" to profiles.isNotEmpty(),
                "profiles" to profiles,
                "maxLuminance" to (caps?.desiredMaxLuminance?.toDouble() ?: 0.0)
            )
        } else {
            mapOf("isHdrSupported" to false, "profiles" to listOf<String>(), "maxLuminance" to 0.0)
        }
    }
}
