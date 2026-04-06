package com.viocha.nodeverify.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.unit.dp
import com.viocha.nodeverify.model.ActionUiState
import com.viocha.nodeverify.model.PlaygroundAction
import com.viocha.nodeverify.model.parseAction
import com.viocha.nodeverify.ui.components.BrokenCard
import com.viocha.nodeverify.ui.components.CardShell
import com.viocha.nodeverify.ui.components.KeyValueRow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

@Composable
fun PlaygroundScreen(
    runNodeCommand: (String, String) -> String
) {
    Column {
        HttpServerCard(runNodeCommand = runNodeCommand)

        Spacer(modifier = Modifier.height(16.dp))

        PlaygroundFeatureCard(
            title = "Crypto Playground",
            description = "Hash arbitrary input, generate a UUID, and inspect its byte layout through Node.",
            action = PlaygroundAction.Crypto,
            runNodeCommand = runNodeCommand
        ) { trigger, loading ->
            var text by rememberSaveable { mutableStateOf("Node.js on Android via crypto") }
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Text to hash") },
                minLines = 2
            )
            Spacer(modifier = Modifier.height(12.dp))
            LoadingTextButton(
                label = "Run Hash",
                onClick = { trigger(JSONObject().put("text", text).toString()) },
                loading = loading
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        PlaygroundFeatureCard(
            title = "Compression Playground",
            description = "Send text through Node zlib and inspect the compressed payload size.",
            action = PlaygroundAction.Gzip,
            runNodeCommand = runNodeCommand
        ) { trigger, loading ->
            var text by rememberSaveable { mutableStateOf("Compose dashboard -> Node zlib -> Android") }
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Text to compress") },
                minLines = 2
            )
            Spacer(modifier = Modifier.height(12.dp))
            LoadingTextButton(
                label = "Run Compression",
                onClick = { trigger(JSONObject().put("text", text).toString()) },
                loading = loading
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        PlaygroundFeatureCard(
            title = "Filesystem Playground",
            description = "Write your current text into app storage through Node fs and read it back.",
            action = PlaygroundAction.Filesystem,
            runNodeCommand = runNodeCommand
        ) { trigger, loading ->
            var text by rememberSaveable { mutableStateOf("Persisted by Node into Android app storage.") }
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("File contents") },
                minLines = 2
            )
            Spacer(modifier = Modifier.height(12.dp))
            LoadingTextButton(
                label = "Write File",
                onClick = { trigger(JSONObject().put("text", text).toString()) },
                loading = loading
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        PlaygroundFeatureCard(
            title = "Intl Playground",
            description = "Choose your own locale and let Node + full ICU format data with it.",
            action = PlaygroundAction.Intl,
            runNodeCommand = runNodeCommand
        ) { trigger, loading ->
            var text by rememberSaveable { mutableStateOf("Node.js在安卓上稳定运行") }
            var locale by rememberSaveable { mutableStateOf("zh-CN") }
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Text for segmentation") },
                minLines = 2
            )
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedTextField(
                value = locale,
                onValueChange = { locale = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Locale") },
                singleLine = true
            )
            Spacer(modifier = Modifier.height(12.dp))
            LoadingTextButton(
                label = "Run Intl",
                onClick = {
                    trigger(
                        JSONObject()
                            .put("text", text)
                            .put("locale", locale)
                            .toString()
                    )
                },
                loading = loading
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        PlaygroundFeatureCard(
            title = "URL Playground",
            description = "Paste a URL or any text and let Node's WHATWG URL parser normalize it.",
            action = PlaygroundAction.Url,
            runNodeCommand = runNodeCommand
        ) { trigger, loading ->
            var text by rememberSaveable { mutableStateOf("https://node.android.demo/runtime?q=compose") }
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("URL or query text") },
                minLines = 2
            )
            Spacer(modifier = Modifier.height(12.dp))
            LoadingTextButton(
                label = "Parse URL",
                onClick = { trigger(JSONObject().put("text", text).toString()) },
                loading = loading
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        PlaygroundFeatureCard(
            title = "Timer Playground",
            description = "Trigger a live delay measurement from Node's timer promises API.",
            action = PlaygroundAction.Timers,
            runNodeCommand = runNodeCommand
        ) { trigger, loading ->
            var text by rememberSaveable { mutableStateOf("Measure a timer in the Node event loop") }
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Annotation text") },
                minLines = 2
            )
            Spacer(modifier = Modifier.height(12.dp))
            LoadingTextButton(
                label = "Measure Timer",
                onClick = { trigger(JSONObject().put("text", text).toString()) },
                loading = loading
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HttpServerCard(
    runNodeCommand: (String, String) -> String
) {
    val scope = rememberCoroutineScope()
    var state by remember { mutableStateOf<ActionUiState>(ActionUiState.Idle) }
    var activeCommand by remember { mutableStateOf<String?>(null) }
    var serverRunning by rememberSaveable { mutableStateOf(false) }

    CardShell(title = "HTTP Server Playground") {
        Text(
            text = "Boot a real Node HTTP server inside the app, send a request to it, then shut it down cleanly.",
            style = MaterialTheme.typography.bodyMedium,
            color = Color(0xFF655345)
        )
        Spacer(modifier = Modifier.height(14.dp))
        KeyValueRow(
            com.viocha.nodeverify.model.NodeItem(
                label = "Endpoint",
                value = "http://127.0.0.1:8123/"
            )
        )
        Spacer(modifier = Modifier.height(14.dp))

        fun trigger(mode: String) {
            activeCommand = mode
            state = ActionUiState.Loading(PlaygroundAction.HttpServer)
            scope.launch {
                val raw = withContext(Dispatchers.IO) {
                    runNodeCommand(mode, "{}")
                }
                activeCommand = null
                val parsed = parseAction(raw)
                if (parsed != null) {
                    if (parsed.status != "error") {
                        when (mode) {
                            "http-server-start" -> serverRunning = true
                            "http-server-stop" -> serverRunning = false
                        }
                    }
                    state = ActionUiState.Ready(parsed)
                } else {
                    state = ActionUiState.Broken(raw)
                }
            }
        }

        FlowRow(
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(10.dp),
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(10.dp)
        ) {
            if (serverRunning) {
                HttpActionButton(
                    label = "Stop Server",
                    loading = activeCommand == "http-server-stop",
                    enabled = activeCommand == null,
                    onClick = { trigger("http-server-stop") }
                )
            } else {
                HttpActionButton(
                    label = "Start Server",
                    loading = activeCommand == "http-server-start",
                    enabled = activeCommand == null,
                    onClick = { trigger("http-server-start") }
                )
            }
            HttpActionButton(
                label = "Send Request",
                loading = activeCommand == "http-server-request",
                enabled = activeCommand == null && serverRunning,
                onClick = { trigger("http-server-request") }
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        when (val current = state) {
            ActionUiState.Idle -> Unit

            is ActionUiState.Broken -> {
                BrokenCard(current.rawOutput)
            }

            is ActionUiState.Ready -> {
                current.result.items.forEachIndexed { index, item ->
                    if (index > 0) Spacer(modifier = Modifier.height(10.dp))
                    KeyValueRow(item)
                }
            }

            is ActionUiState.Loading -> Unit
        }
    }
}

@Composable
private fun HttpActionButton(
    label: String,
    loading: Boolean,
    enabled: Boolean,
    onClick: () -> Unit
) {
    val contentColor = LocalContentColor.current

    Button(
        onClick = onClick,
        enabled = enabled
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                text = label,
                modifier = Modifier.alpha(if (loading) 0f else 1f)
            )
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp,
                    color = contentColor
                )
            }
        }
    }
}

@Composable
private fun LoadingTextButton(
    label: String,
    onClick: () -> Unit,
    loading: Boolean
) {
    val contentColor = LocalContentColor.current

    Button(
        onClick = onClick,
        enabled = !loading
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                text = label,
                modifier = Modifier.alpha(if (loading) 0f else 1f)
            )
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp,
                    color = contentColor
                )
            }
        }
    }
}

@Composable
private fun PlaygroundFeatureCard(
    title: String,
    description: String,
    action: PlaygroundAction,
    runNodeCommand: (String, String) -> String,
    controls: @Composable (trigger: (String) -> Unit, loading: Boolean) -> Unit
) {
    val scope = rememberCoroutineScope()
    var state by remember(action.mode) { mutableStateOf<ActionUiState>(ActionUiState.Idle) }

    CardShell(title = title) {
        Text(
            text = description,
            style = MaterialTheme.typography.bodyMedium,
            color = Color(0xFF655345)
        )
        Spacer(modifier = Modifier.height(14.dp))

        controls({ payload ->
            state = ActionUiState.Loading(action)
            scope.launch {
                val raw = withContext(Dispatchers.IO) {
                    runNodeCommand(action.mode, payload)
                }
                state = parseAction(raw)?.let { ActionUiState.Ready(it) }
                    ?: ActionUiState.Broken(raw)
            }
        }, state is ActionUiState.Loading)

        Spacer(modifier = Modifier.height(16.dp))

        when (val current = state) {
            ActionUiState.Idle -> Unit

            is ActionUiState.Loading -> Unit

            is ActionUiState.Broken -> {
                BrokenCard(current.rawOutput)
            }

            is ActionUiState.Ready -> {
                current.result.items.forEachIndexed { index, item ->
                    if (index > 0) Spacer(modifier = Modifier.height(10.dp))
                    KeyValueRow(item)
                }
            }
        }
    }
}
