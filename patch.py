import os

file_path = r'c:\Users\manit\Downloads\wfy\android\app\src\main\kotlin\com\jarvis\jarvis_ai\JarvisAccessibilityService.kt'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

# Replace return types for gestures
text = text.replace('fun performTap(x: Int, y: Int): Boolean {', 'fun performTap(x: Int, y: Int): String {')
text = text.replace('return dispatchGesture(gesture, null, null)', 'val result = dispatchGesture(gesture, null, null)\n        return if (result) "OK" else "ERROR"')

text = text.replace('fun performLongPress(x: Int, y: Int): Boolean {', 'fun performLongPress(x: Int, y: Int): String {')
text = text.replace('fun performDoubleTap(x: Int, y: Int): Boolean {', 'fun performDoubleTap(x: Int, y: Int): String {')
text = text.replace('fun performSwipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Long = 300): Boolean {', 'fun performSwipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Long = 300): String {')
text = text.replace('fun performScrollDown(): Boolean {', 'fun performScrollDown(): String {')
text = text.replace('fun performScrollUp(): Boolean {', 'fun performScrollUp(): String {')

text = text.replace('val root = rootInActiveWindow ?: return false', 'val root = rootInActiveWindow ?: return "ERROR: no root"')
text = text.replace('return scrollable.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)', 'val res = scrollable.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)\n            return if(res) "OK" else "ERROR"')
text = text.replace('return scrollable.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)', 'val res = scrollable.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)\n            return if(res) "OK" else "ERROR"')

# Replace other actions
text = text.replace('fun typeText(text: String): Boolean {', 'fun typeText(text: String): String {')
text = text.replace('fun clearText(): Boolean {', 'fun clearText(): String {')
text = text.replace('fun pasteFromClipboard(): Boolean {', 'fun pasteFromClipboard(): String {')
text = text.replace('fun clickNodeByText(text: String, ignoreCase: Boolean = true): Boolean {', 'fun clickNodeByText(text: String, ignoreCase: Boolean = true): String {')
text = text.replace('fun focusNodeByText(text: String, ignoreCase: Boolean = true): Boolean {', 'fun focusNodeByText(text: String, ignoreCase: Boolean = true): String {')
text = text.replace('fun pressBack(): Boolean {', 'fun pressBack(): String {')
text = text.replace('fun pressHome(): Boolean {', 'fun pressHome(): String {')
text = text.replace('fun pressRecents(): Boolean {', 'fun pressRecents(): String {')
text = text.replace('fun pressNotifications(): Boolean {', 'fun pressNotifications(): String {')
text = text.replace('fun pressQuickSettings(): Boolean {', 'fun pressQuickSettings(): String {')
text = text.replace('fun launchApp(packageName: String): Boolean {', 'fun launchApp(packageName: String): String {')
text = text.replace('fun launchAppByName(appName: String): Boolean {', 'fun launchAppByName(appName: String): String {')
text = text.replace('fun openUrl(url: String): Boolean {', 'fun openUrl(url: String): String {')
text = text.replace('fun dismissAllNotifications(): Boolean {', 'fun dismissAllNotifications(): String {')
text = text.replace('fun clickRef(ref: String): Boolean {', 'fun clickRef(ref: String): String {')
text = text.replace('fun typeIntoRef(ref: String, text: String, clearFirst: Boolean = false): Boolean {', 'fun typeIntoRef(ref: String, text: String, clearFirst: Boolean = false): String {')
text = text.replace('fun scrollRef(ref: String, direction: String = "down"): Boolean {', 'fun scrollRef(ref: String, direction: String = "down"): String {')

text = text.replace('return performGlobalAction(GLOBAL_ACTION_BACK)', 'val res = performGlobalAction(GLOBAL_ACTION_BACK)\n        return if(res) "OK" else "ERROR"')
text = text.replace('return performGlobalAction(GLOBAL_ACTION_HOME)', 'val res = performGlobalAction(GLOBAL_ACTION_HOME)\n        return if(res) "OK" else "ERROR"')
text = text.replace('return performGlobalAction(GLOBAL_ACTION_RECENTS)', 'val res = performGlobalAction(GLOBAL_ACTION_RECENTS)\n        return if(res) "OK" else "ERROR"')
text = text.replace('return performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)', 'val res = performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)\n        return if(res) "OK" else "ERROR"')
text = text.replace('return performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)', 'val res = performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)\n        return if(res) "OK" else "ERROR"')

text = text.replace('return true', 'return "OK"')
text = text.replace('return false', 'return "ERROR"')
text = text.replace('return "ERROR"\n        }', 'return "ERROR"\n    }')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)
print("done")
