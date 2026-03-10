package com.calday.app

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.webkit.JsPromptResult
import android.webkit.JsResult
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat

class MainActivity : AppCompatActivity() {

    lateinit var webView: WebView
        private set
    private lateinit var billingManager: BillingManager
    private var pendingImportData: String? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Edge-to-edge display
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = android.graphics.Color.TRANSPARENT
        window.navigationBarColor = android.graphics.Color.TRANSPARENT

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = true
            settings.databaseEnabled = true
            settings.setSupportZoom(false)
            settings.loadWithOverviewMode = true
            settings.useWideViewPort = true

            // Prevent long-press selection
            setOnLongClickListener { true }
            isHapticFeedbackEnabled = false

            overScrollMode = View.OVER_SCROLL_NEVER
        }

        setContentView(webView)

        // Billing setup
        billingManager = BillingManager(this)

        // JavaScript interface
        val webInterface = WebAppInterface(this, billingManager)
        billingManager.webAppInterface = webInterface
        webView.addJavascriptInterface(webInterface, "AndroidBridge")

        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                // Inject Android bridge adapter so HTML can use the same API as iOS
                injectBridgeAdapter()
                // Handle pending import data
                pendingImportData?.let { data ->
                    webView.evaluateJavascript("window.importFromURL('$data');", null)
                    pendingImportData = null
                }
            }

            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: android.webkit.WebResourceRequest?
            ): Boolean {
                val url = request?.url ?: return false
                if (url.scheme == "calday" && url.host == "import") {
                    handleImportUrl(url)
                    return true
                }
                return false
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onJsAlert(
                view: WebView?, url: String?, message: String?, result: JsResult?
            ): Boolean {
                AlertDialog.Builder(this@MainActivity)
                    .setMessage(message)
                    .setPositiveButton("OK") { _, _ -> result?.confirm() }
                    .setCancelable(false)
                    .show()
                return true
            }

            override fun onJsConfirm(
                view: WebView?, url: String?, message: String?, result: JsResult?
            ): Boolean {
                AlertDialog.Builder(this@MainActivity)
                    .setMessage(message)
                    .setPositiveButton("OK") { _, _ -> result?.confirm() }
                    .setNegativeButton("キャンセル") { _, _ -> result?.cancel() }
                    .setCancelable(false)
                    .show()
                return true
            }

            override fun onJsPrompt(
                view: WebView?, url: String?, message: String?,
                defaultValue: String?, result: JsPromptResult?
            ): Boolean {
                result?.confirm(defaultValue)
                return true
            }
        }

        // Load HTML
        webView.loadUrl("file:///android_asset/index.html")

        // Handle intent if launched via URL scheme
        handleIntent(intent)
    }

    /**
     * Inject a bridge adapter so the existing HTML/JS code works on Android.
     * Maps the iOS `window.webkit.messageHandlers.store.postMessage()` pattern
     * to the Android `AndroidBridge` JavascriptInterface.
     */
    private fun injectBridgeAdapter() {
        val js = """
            (function() {
                if (window._androidBridgeReady) return;
                window._androidBridgeReady = true;

                // Create webkit.messageHandlers.store compatible interface
                if (!window.webkit) window.webkit = {};
                if (!window.webkit.messageHandlers) window.webkit.messageHandlers = {};
                window.webkit.messageHandlers.store = {
                    postMessage: function(msg) {
                        if (typeof AndroidBridge !== 'undefined') {
                            AndroidBridge.postMessage(JSON.stringify(msg));
                        }
                    }
                };
            })();
        """.trimIndent()
        webView.evaluateJavascript(js, null)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme == "calday" && uri.host == "import") {
            handleImportUrl(uri)
        }
    }

    private fun handleImportUrl(uri: Uri) {
        val data = uri.getQueryParameter("data") ?: return
        // If WebView is ready, inject immediately; otherwise queue
        pendingImportData = data
        webView.evaluateJavascript(
            "if (typeof window.importFromURL === 'function') { window.importFromURL('$data'); }",
            null
        )
    }

    override fun onDestroy() {
        billingManager.destroy()
        webView.destroy()
        super.onDestroy()
    }

    @Deprecated("Use onBackPressedDispatcher")
    override fun onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }
}
