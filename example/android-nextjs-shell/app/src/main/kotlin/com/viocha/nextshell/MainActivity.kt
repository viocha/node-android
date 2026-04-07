package com.viocha.nextshell

import android.graphics.Bitmap
import android.graphics.Color
import android.os.Bundle
import android.view.ViewGroup
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.OnBackPressedCallback
import androidx.activity.ComponentActivity
import androidx.core.view.WindowCompat
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import com.viocha.nextshell.runtime.NextBundleInstaller
import com.viocha.nextshell.runtime.parseLaunchResult
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : ComponentActivity() {
    companion object {
        private const val PRIVATE_ORIGIN = "http://localhost/"
        private const val BOOTSTRAP_BASE_URL = "${PRIVATE_ORIGIN}__bootstrap_loading__"
        private const val BOOTSTRAP_ASSET_NAME = "bootstrap-loading.html"
        private const val TAG = "NextShell"

        init {
            System.loadLibrary("c++_shared")
            System.loadLibrary("nextshell")
        }

        @JvmStatic
        private external fun startNextServer(
            appDir: String,
            cacheDir: String
        ): String
    }

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private lateinit var bootstrapHtml: String
    private var webView: WebView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        bootstrapHtml =
            assets.open(BOOTSTRAP_ASSET_NAME).use {
                String(it.readBytes(), StandardCharsets.UTF_8)
            }
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.WHITE
        window.navigationBarColor = Color.WHITE
        window.decorView.setBackgroundColor(Color.WHITE)
        WindowCompat.setDecorFitsSystemWindows(window, true)

        val currentWebView =
            WebView(this).apply {
                layoutParams =
                    ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    )
            }
        webView = currentWebView
        configureWebView(currentWebView)
        setContentView(currentWebView)
        currentWebView.loadDataWithBaseURL(
            BOOTSTRAP_BASE_URL,
            bootstrapHtml,
            "text/html",
            "UTF-8",
            null,
        )
        startBootstrap()

        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    val currentWebView = webView
                    if (currentWebView != null && currentWebView.canGoBack()) {
                        currentWebView.goBack()
                        return
                    }
                    isEnabled = false
                    onBackPressedDispatcher.onBackPressed()
                }
            },
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        executor.shutdownNow()
        webView?.removeAllViews()
        webView?.destroy()
        webView = null
    }

    override fun onResume() {
        super.onResume()
        webView?.invalidate()
    }

    private fun configureWebView(webView: WebView) {
        webView.setBackgroundColor(Color.WHITE)
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
                override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                    super.onPageStarted(view, url, favicon)
                }

                override fun onReceivedError(
                    view: WebView?,
                    request: WebResourceRequest?,
                    error: WebResourceError?,
                ) {
                    super.onReceivedError(view, request, error)
                    if (request?.isForMainFrame == true) {
                        showError(error?.description?.toString() ?: "Unable to open page")
                    }
                }
            }
    }

    private fun startBootstrap() {
        updateBootstrapUi("window.NextShellBootstrapUi?.showLoading('Loading…')")
        executor.execute {
            try {
                val installDir = runBlocking { NextBundleInstaller.prepare(this@MainActivity) }
                val raw = startNextServer(installDir.absolutePath, cacheDir.absolutePath)
                val result = parseLaunchResult(raw)

                if (result != null &&
                    result.status == "success" &&
                    result.url.isNotBlank() &&
                    result.proxyUrl.isNotBlank()
                ) {
                    runOnUiThread {
                        applyProxyAndLoadApp(result.proxyUrl, result.url)
                    }
                } else {
                    val detail = result?.detail?.ifBlank { raw } ?: raw
                    runOnUiThread { showError(detail) }
                }
            } catch (error: Exception) {
                runOnUiThread { showError(error.message ?: error.toString()) }
            }
        }
    }

    private fun applyProxyAndLoadApp(
        proxyUrl: String,
        appUrl: String,
    ) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            showError("Proxy override unavailable")
            return
        }

        ProxyController.getInstance().setProxyOverride(
            ProxyConfig.Builder()
                .addProxyRule(proxyUrl)
                .removeImplicitRules()
                .addBypassRule("localhost")
                .apply {
                    if (WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE_REVERSE_BYPASS)) {
                        setReverseBypassEnabled(true)
                    }
                }
                .build(),
            mainExecutor,
        ) {
            updateBootstrapUi("window.NextShellBootstrapUi?.openApp(${JSONObject.quote(appUrl)})")
        }
    }

    private fun showError(message: String) {
        updateBootstrapUi("window.NextShellBootstrapUi?.showError(${JSONObject.quote(message)})")
    }

    private fun updateBootstrapUi(script: String) {
        webView?.post {
            webView?.evaluateJavascript(script, null)
        }
    }
}
