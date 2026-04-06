package com.viocha.nodeverify.model

import org.json.JSONArray
import org.json.JSONObject

fun parseReport(payload: String): NodeReport? {
    val root = runCatching { JSONObject(payload) }.getOrNull() ?: return null
    if (root.optString("kind") != "report") return null
    return NodeReport(
        stats = root.optJSONArray("stats").toStats(),
        highlights = root.optJSONArray("highlights").toStrings(),
        checks = root.optJSONArray("checks").toChecks()
    )
}

fun parseAction(payload: String): NodeActionResult? {
    val root = runCatching { JSONObject(payload) }.getOrNull() ?: return null
    if (root.optString("kind") != "action") return null
    return NodeActionResult(
        status = root.optString("status"),
        items = root.optJSONArray("items").toItems()
    )
}

private fun JSONArray?.toStrings(): List<String> {
    if (this == null) return emptyList()
    return buildList {
        for (index in 0 until length()) {
            add(optString(index))
        }
    }
}

private fun JSONArray?.toStats(): List<NodeStat> {
    if (this == null) return emptyList()
    return buildList {
        for (index in 0 until length()) {
            val item = optJSONObject(index) ?: continue
            add(NodeStat(item.optString("label"), item.optString("value")))
        }
    }
}

private fun JSONArray?.toChecks(): List<NodeCheck> {
    if (this == null) return emptyList()
    return buildList {
        for (index in 0 until length()) {
            val item = optJSONObject(index) ?: continue
            add(
                NodeCheck(
                    id = item.optString("id"),
                    title = item.optString("title"),
                    ok = item.optBoolean("ok"),
                    detail = item.optString("detail")
                )
            )
        }
    }
}

private fun JSONArray?.toItems(): List<NodeItem> {
    if (this == null) return emptyList()
    return buildList {
        for (index in 0 until length()) {
            val item = optJSONObject(index) ?: continue
            add(NodeItem(item.optString("label"), item.optString("value")))
        }
    }
}
