package com.jarvis.jarvis_ai

import android.graphics.Rect
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo

/**
 * GAP 1 FIX: Stable @eN ref IDs across snapshots.
 *
 * Key insight: refs are assigned by DEPTH-FIRST TREE POSITION, not memory
 * address. As long as the screen doesn't change layout, @e5 will always be
 * the same logical node — exactly like OpenClaw's CDP snapshot.
 *
 * Nodes are stored via AccessibilityNodeInfo.obtain() — a fresh copy that
 * Android won't recycle from under us between snapshot and click.
 */
class JarvisSnapshotEngine {

    // ref → fresh copy of node (obtain'd so Android won't recycle it)
    private val refMap = mutableMapOf<String, AccessibilityNodeInfo>()
    private var counter = 0

    // ─── PUBLIC: Take snapshot ─────────────────────────────────────────────
    fun takeSnapshot(root: AccessibilityNodeInfo): SnapshotResult {
        // Release all previously obtain'd copies
        refMap.values.forEach { runCatching { it.recycle() } }
        refMap.clear()
        counter = 0

        val elements = mutableListOf<SnapElement>()
        walkNode(root, elements, depth = 0)

        return SnapshotResult(
            packageName = root.packageName?.toString() ?: "",
            elements = elements,
            refMap = refMap
        )
    }

    // ─── STABLE WALK: depth-first, deterministic ref numbering ────────────
    private fun walkNode(
        node: AccessibilityNodeInfo?,
        out: MutableList<SnapElement>,
        depth: Int
    ) {
        if (node == null || depth > 60) return

        // Assign ref BEFORE children — parent always lower ref than children
        val ref = "@e${++counter}"

        // Store a fresh obtain'd copy so Android can't recycle it
        try {
            refMap[ref] = AccessibilityNodeInfo.obtain(node)
        } catch (_: Exception) { /* node already recycled — skip */ }

        val bounds = Rect()
        node.getBoundsInScreen(bounds)

        val text = node.text?.toString()?.trim()?.take(80) ?: ""
        val desc = node.contentDescription?.toString()?.trim()?.take(60) ?: ""
        val viewId = node.viewIdResourceName?.substringAfterLast('/') ?: ""
        val cls = node.className?.toString()?.substringAfterLast('.') ?: "View"
        val clickable = node.isClickable
        val editable = node.isEditable
        val scrollable = node.isScrollable
        val enabled = node.isEnabled
        val focused = node.isFocused
        val checked = node.isChecked

        val hasContent = text.isNotEmpty() || desc.isNotEmpty() || viewId.isNotEmpty()
        val isInteractive = clickable || editable || scrollable
        val visible = bounds.width() > 0 && bounds.height() > 0

        if ((hasContent || isInteractive) && visible) {
            out.add(
                SnapElement(
                    ref = ref,
                    cls = cls,
                    text = text.ifEmpty { desc },
                    viewId = viewId,
                    clickable = clickable,
                    editable = editable,
                    scrollable = scrollable,
                    enabled = enabled,
                    focused = focused,
                    checked = checked,
                    cx = bounds.centerX(),
                    cy = bounds.centerY(),
                    bounds = bounds
                )
            )
        }

        // Visit children in order — preserves stable numbering
        for (i in 0 until node.childCount) {
            walkNode(node.getChild(i), out, depth + 1)
        }
    }

    // ─── CLICK by ref — direct ACTION_CLICK, no coordinate guessing ───────
    fun clickRef(ref: String): Boolean {
        val node = refMap[ref] ?: return false
        return try {
            if (node.isClickable) {
                node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            } else {
                // Walk up to find clickable ancestor (max 5 levels)
                var parent = node.parent
                var depth = 0
                while (parent != null && depth < 5) {
                    if (parent.isClickable) {
                        return parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    }
                    parent = parent.parent
                    depth++
                }
                false
            }
        } catch (_: Exception) { false }
    }

    // ─── TYPE into ref — ACTION_SET_TEXT, optionally clear first ──────────
    fun typeIntoRef(ref: String, text: String, clearFirst: Boolean): Boolean {
        val node = refMap[ref] ?: return false
        return try {
            node.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS)
            if (clearFirst) {
                // Select all text then replace
                val selectArgs = Bundle().apply {
                    putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, 0)
                    putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, 9999)
                }
                node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selectArgs)
            }
            val typeArgs = Bundle().apply {
                putCharSequence(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text
                )
            }
            node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, typeArgs)
        } catch (_: Exception) { false }
    }

    // ─── SCROLL ref ────────────────────────────────────────────────────────
    fun scrollRef(ref: String, direction: String): Boolean {
        val node = refMap[ref] ?: return false
        return try {
            when (direction) {
                "up" -> node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
                else -> node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
            }
        } catch (_: Exception) { false }
    }

    // ─── FIND ref by text content ──────────────────────────────────────────
    fun findRefByText(text: String): String? =
        refMap.entries.firstOrNull { (_, node) ->
            val t = node.text?.toString() ?: ""
            val d = node.contentDescription?.toString() ?: ""
            t.contains(text, ignoreCase = true) || d.contains(text, ignoreCase = true)
        }?.key

    // ─── GET bounds of a ref ──────────────────────────────────────────────
    fun getRefBounds(ref: String): String {
        val node = refMap[ref] ?: return ""
        val b = Rect()
        node.getBoundsInScreen(b)
        return "{\"cx\":${b.centerX()},\"cy\":${b.centerY()}," +
               "\"left\":${b.left},\"top\":${b.top}," +
               "\"right\":${b.right},\"bottom\":${b.bottom}}"
    }

    // ─── CLEANUP ──────────────────────────────────────────────────────────
    fun dispose() {
        refMap.values.forEach { runCatching { it.recycle() } }
        refMap.clear()
    }
}

// ─── Data classes ─────────────────────────────────────────────────────────────
data class SnapElement(
    val ref: String,
    val cls: String,
    val text: String,
    val viewId: String,
    val clickable: Boolean,
    val editable: Boolean,
    val scrollable: Boolean,
    val enabled: Boolean,
    val focused: Boolean,
    val checked: Boolean,
    val cx: Int,
    val cy: Int,
    val bounds: Rect
) {
    /** Compact AI-readable line — like OpenClaw's CDP snapshot output */
    fun toAILine(): String {
        val sb = StringBuilder("$ref [$cls]")
        if (text.isNotEmpty()) sb.append(" \"$text\"")
        if (viewId.isNotEmpty()) sb.append(" #$viewId")
        if (clickable) sb.append(" [click]")
        if (editable) sb.append(" [input]")
        if (scrollable) sb.append(" [scroll]")
        if (focused) sb.append(" *focused*")
        if (!enabled) sb.append(" (disabled)")
        if (checked) sb.append(" ✓")
        sb.append(" @($cx,$cy)")
        return sb.toString()
    }
}

data class SnapshotResult(
    val packageName: String,
    val elements: List<SnapElement>,
    val refMap: Map<String, AccessibilityNodeInfo>
) {
    fun toAIReadable(): String {
        val interactive = elements.filter { it.clickable || it.editable || it.scrollable }
        val info = elements.filter {
            !it.clickable && !it.editable && !it.scrollable && it.text.isNotEmpty()
        }
        return buildString {
            appendLine("📱 $packageName | ${elements.size} elements")
            appendLine("─".repeat(48))
            if (interactive.isNotEmpty()) {
                appendLine("INTERACTIVE (use these refs for actions):")
                interactive.forEach { appendLine("  ${it.toAILine()}") }
            }
            if (info.isNotEmpty()) {
                appendLine("INFO:")
                info.take(15).forEach { appendLine("  ${it.ref} \"${it.text}\"") }
            }
        }
    }

    fun findByText(query: String) =
        elements.firstOrNull { it.text.contains(query, ignoreCase = true) }

    fun findByRef(ref: String) = elements.firstOrNull { it.ref == ref }
}
