package com.viocha.nextshell.ui

import android.annotation.SuppressLint
import android.util.Log
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

private const val PrivateOrigin = "http://localhost/"
private const val BootstrapBaseUrl = "${PrivateOrigin}__bootstrap_loading__"
private const val BootstrapAssetName = "bootstrap-loading.html"
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
    val bootstrapHtml = remember {
        context.assets.open(BootstrapAssetName).use {
            String(it.readBytes(), StandardCharsets.UTF_8)
        }
    }
    var launchNonce by rememberSaveable { mutableIntStateOf(0) }
    var webViewRef by remember { mutableStateOf<WebView?>(null) }

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

    LaunchedEffect(webViewRef, shellState) {
        val webView = webViewRef ?: return@LaunchedEffect
        when (val state = shellState) {
            is ShellUiState.Loading -> {
                loadBootstrapPage(webView, bootstrapHtml)
                updateBootstrapUi(
                    webView,
                    "window.NextShellBootstrapUi?.showLoading(${JSONObject.quote(state.message)})"
                )
            }

            is ShellUiState.Ready -> {
                updateBootstrapUi(
                    webView,
                    "window.NextShellBootstrapUi?.openApp(${JSONObject.quote(state.url)})"
                )
            }

            is ShellUiState.Error -> {
                loadBootstrapPage(webView, bootstrapHtml)
                updateBootstrapUi(
                    webView,
                    "window.NextShellBootstrapUi?.showError(${JSONObject.quote(state.message)})"
                )
            }
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        AndroidView(
            factory = { androidContext ->
                WebView(androidContext).apply {
                    webViewRef = this
                    configureWebView(this)
                    loadBootstrapPage(this, bootstrapHtml)
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
            modifier = Modifier.fillMaxSize()
        )

        if (shellState is ShellUiState.Error) {
            ErrorPanel(
                message = (shellState as ShellUiState.Error).message,
                onRetry = { launchNonce += 1 },
            )
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
                    .addProxyRule(proxyRule)
                    .removeImplicitRules()
                    .addBypassRule("localhost")
                    .apply {
                        if (WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE_REVERSE_BYPASS)) {
                            setReverseBypassEnabled(true)
                        }
                    }
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
private fun configureWebView(
    webView: WebView
) {
    webView.setBackgroundColor(WebSurfaceColor)
    webView.isVerticalScrollBarEnabled = false
    webView.isHorizontalScrollBarEnabled = false
    webView.settings.apply {
        javaScriptEnabled = true
        domStorageEnabled = true
        loadsImagesAutomatically = true
        cacheMode = WebSettings.LOAD_DEFAULT
        allowFileAccess = false
        allowContentAccess = false
    }
    webView.webViewClient =
        object : WebViewClient() {
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
                }
            }
        }
}

private fun loadBootstrapPage(
    webView: WebView,
    bootstrapHtml: String
) {
    webView.loadDataWithBaseURL(
        BootstrapBaseUrl,
        bootstrapHtml,
        "text/html",
        "UTF-8",
        null,
    )
}

private fun updateBootstrapUi(
    webView: WebView,
    script: String
) {
    webView.post {
        webView.evaluateJavascript(script, null)
    }
}
