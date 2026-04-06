package com.viocha.nextshell.ui

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.util.Log
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import com.viocha.nextshell.runtime.NextBundleInstaller
import com.viocha.nextshell.runtime.parseLaunchResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

private const val PrivateOrigin = "http://focusboard.invalid/"
private const val ShellTag = "NextShell"
private const val LoadingMessage = "Loading…"
private const val WebSurfaceColor = 0xFFF8F0E5.toInt()

private sealed interface ShellUiState {
    data class Loading(val message: String) : ShellUiState
    data class Ready(val url: String) : ShellUiState
    data class Error(val message: String) : ShellUiState
}

@Composable
fun NextShellApp(
    startNextServer: (String) -> String
) {
    val context = LocalContext.current
    var launchNonce by rememberSaveable { mutableIntStateOf(0) }

    val shellState by produceState<ShellUiState>(
        initialValue = ShellUiState.Loading(LoadingMessage),
        key1 = launchNonce
    ) {
        clearWebViewProxyOverride(context)
        value = ShellUiState.Loading(LoadingMessage)

        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            value = ShellUiState.Error(
                "This WebView build does not support proxy override, so a private app origin cannot be created on this device."
            )
            return@produceState
        }

        val installDir = runCatching {
            withContext(Dispatchers.IO) { NextBundleInstaller.prepare(context) }
        }.getOrElse { error ->
            value = ShellUiState.Error("Asset extraction failed: ${error.message}")
            return@produceState
        }

        val raw = withContext(Dispatchers.IO) {
            startNextServer(installDir.absolutePath)
        }
        val result = parseLaunchResult(raw)

        value = when {
            result == null -> ShellUiState.Error(raw)
            result.status == "success" &&
                result.url.isNotBlank() &&
                result.proxyUrl.isNotBlank() -> {
                runCatching {
                    applyWebViewProxyOverride(
                        proxyRule = result.proxyUrl,
                        context = context
                    )
                }.fold(
                    onSuccess = {
                        Log.i(ShellTag, "Applied WebView proxy override for $PrivateOrigin via ${result.proxyUrl}")
                        ShellUiState.Ready(url = result.url)
                    },
                    onFailure = { error ->
                        ShellUiState.Error("Failed to apply WebView proxy override: ${error.message}")
                    }
                )
            }

            else -> ShellUiState.Error(result?.detail?.ifBlank { "App startup failed." } ?: raw)
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            clearWebViewProxyOverride(context)
        }
    }

    val backgroundBrush = remember {
        Brush.verticalGradient(
            colors = listOf(
                Color(0xFFFFF7EE),
                Color(0xFFF8F0E5),
                Color(0xFFF1E6DA)
            )
        )
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(backgroundBrush)
    ) {
        when (val state = shellState) {
            is ShellUiState.Loading -> LoadingPanel(state.message)
            is ShellUiState.Error -> ErrorPanel(
                message = state.message,
                onRetry = { launchNonce += 1 }
            )

            is ShellUiState.Ready -> WebAppPanel(url = state.url)
        }
    }
}

@Composable
private fun LoadingPanel(message: String) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Surface(
            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
            tonalElevation = 2.dp,
            shadowElevation = 2.dp,
            shape = MaterialTheme.shapes.extraLarge,
            modifier = Modifier.padding(22.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(horizontal = 22.dp, vertical = 20.dp)
            ) {
                CircularProgressIndicator(
                    strokeWidth = 2.5.dp,
                    modifier = Modifier.padding(end = 14.dp)
                )
                Text(
                    text = message,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

@Composable
private fun ErrorPanel(
    message: String,
    onRetry: () -> Unit
) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Surface(
            tonalElevation = 1.dp,
            shape = MaterialTheme.shapes.extraLarge,
            modifier = Modifier.padding(22.dp)
        ) {
            Column(
                modifier = Modifier
                    .padding(horizontal = 24.dp, vertical = 22.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                Text(
                    text = "Next.js app failed to open",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "This panel only appears when the embedded app fails to load.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 10.dp)
                )
                SelectionContainer {
                    Text(
                        text = message,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 16.dp)
                    )
                }
                Button(
                    onClick = onRetry,
                    modifier = Modifier.padding(top = 18.dp)
                ) {
                    Text("Retry")
                }
            }
        }
    }
}

private suspend fun applyWebViewProxyOverride(
    proxyRule: String,
    context: android.content.Context
) {
    withContext(Dispatchers.Main) {
        suspendCoroutine { continuation ->
            ProxyController.getInstance().setProxyOverride(
                ProxyConfig.Builder()
                    .addProxyRule(proxyRule, ProxyConfig.MATCH_HTTP)
                    .build(),
                ContextCompat.getMainExecutor(context)
            ) {
                continuation.resume(Unit)
            }
        }
    }
}

private fun clearWebViewProxyOverride(
    context: android.content.Context
) {
    if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) return
    ProxyController.getInstance().clearProxyOverride(
        ContextCompat.getMainExecutor(context)
    ) {}
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun WebAppPanel(
    url: String
) {
    var webError by remember { mutableStateOf<String?>(null) }
    var webViewRef by remember { mutableStateOf<WebView?>(null) }
    var pageCommitted by remember(url) { mutableStateOf(false) }
    val systemBarsPadding = WindowInsets.statusBars.asPaddingValues()
    val navigationPadding = WindowInsets.navigationBars.asPaddingValues()

    Box(modifier = Modifier.fillMaxSize()) {
        AndroidView(
            factory = { context ->
                WebView(context).apply {
                    webViewRef = this
                    setBackgroundColor(WebSurfaceColor)
                    alpha = 0f
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.loadsImagesAutomatically = true
                    settings.cacheMode = WebSettings.LOAD_DEFAULT
                    webViewClient = object : WebViewClient() {
                        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                            webError = null
                            pageCommitted = false
                            view?.alpha = 0f
                        }

                        override fun onPageCommitVisible(view: WebView?, url: String?) {
                            pageCommitted = true
                            view?.animate()?.alpha(1f)?.setDuration(120L)?.start()
                        }

                        override fun onReceivedError(
                            view: WebView?,
                            request: WebResourceRequest?,
                            error: WebResourceError?
                        ) {
                            if (request?.isForMainFrame == true) {
                                Log.e(
                                    ShellTag,
                                    "Main frame load failed for ${request.url}: ${error?.errorCode} ${error?.description}"
                                )
                                webError = error?.description?.toString() ?: "Unknown WebView error"
                            }
                        }
                    }
                    loadUrl(url)
                }
            },
            update = { view ->
                if (view.url != url) {
                    view.loadUrl(url)
                }
            },
            onRelease = { view ->
                if (webViewRef === view) {
                    webViewRef = null
                }
                view.stopLoading()
                view.loadUrl("about:blank")
                view.clearHistory()
                view.removeAllViews()
                view.destroy()
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(top = systemBarsPadding.calculateTopPadding())
                .padding(bottom = navigationPadding.calculateBottomPadding())
        )

        if (!pageCommitted && webError == null) {
            LoadingPanel(message = LoadingMessage)
        }

        if (webError != null) {
            Surface(
                tonalElevation = 2.dp,
                shape = MaterialTheme.shapes.large,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = systemBarsPadding.calculateTopPadding())
                    .padding(16.dp)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp)
                ) {
                    Text(
                        text = "Page load failed",
                        fontWeight = FontWeight.SemiBold
                    )
                    SelectionContainer {
                        Text(
                            text = webError ?: "",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 10.dp)
                        )
                    }
                    Button(
                        onClick = { webViewRef?.reload() },
                        modifier = Modifier.padding(top = 14.dp)
                    ) {
                        Text("Try again")
                    }
                }
            }
        }
    }
}
