package com.viocha.nodeverify.model

enum class ConsoleDestination(val label: String) {
    Overview("Overview"),
    Playground("Playground")
}

enum class PlaygroundAction(
    val mode: String,
    val description: String
) {
    HttpServer("http-server", "Start, hit, and stop a live Node HTTP server"),
    Crypto("crypto", "Run Node crypto on your text"),
    Gzip("gzip", "Use Node zlib to gzip your text"),
    Filesystem("fs", "Persist your text through Node fs"),
    Intl("intl", "Use ICU formatting with your locale"),
    Url("url", "Feed your input into Node URL"),
    Timers("timers", "Let Node await a timer in-process")
}

sealed interface ReportUiState {
    data object Loading : ReportUiState
    data class Ready(val report: NodeReport) : ReportUiState
    data class Broken(val rawOutput: String) : ReportUiState
}

sealed interface ActionUiState {
    data object Idle : ActionUiState
    data class Loading(val action: PlaygroundAction) : ActionUiState
    data class Ready(val result: NodeActionResult) : ActionUiState
    data class Broken(val rawOutput: String) : ActionUiState
}

data class NodeReport(
    val stats: List<NodeStat>,
    val highlights: List<String>,
    val checks: List<NodeCheck>
)

data class NodeStat(
    val label: String,
    val value: String
)

data class NodeCheck(
    val id: String,
    val title: String,
    val ok: Boolean,
    val detail: String
)

data class NodeItem(
    val label: String,
    val value: String
)

data class NodeActionResult(
    val status: String,
    val items: List<NodeItem>
)
