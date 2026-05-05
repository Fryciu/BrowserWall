package com.example.browserfocus

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.ProgressBar
import android.widget.RelativeLayout

/**
 * Osobna aktywność do obsługi OAuth flow innych aplikacji (np. GitHub Mobile).
 * Działa jako vanilla WebView bez żadnych blokad — otwiera się tylko gdy
 * incoming intent zawiera redirect_uri z obcym custom scheme.
 * Po zakończeniu OAuth (redirect na custom scheme) przekazuje URL z powrotem
 * do aplikacji która otworzyła ten flow i zamyka się.
 */
class OAuthWebViewActivity : Activity() {

    private lateinit var webView: WebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val url = intent?.data?.toString() ?: run {
            finish()
            return
        }

        // Prosty layout: pasek postępu + WebView
        val layout = RelativeLayout(this)
        val progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            id = android.R.id.progress
            isIndeterminate = false
            max = 100
        }
        val progressParams = RelativeLayout.LayoutParams(
            RelativeLayout.LayoutParams.MATCH_PARENT,
            8
        )
        layout.addView(progressBar, progressParams)

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
        }

        val webViewParams = RelativeLayout.LayoutParams(
            RelativeLayout.LayoutParams.MATCH_PARENT,
            RelativeLayout.LayoutParams.MATCH_PARENT
        ).apply {
            addRule(RelativeLayout.BELOW, android.R.id.progress)
        }
        layout.addView(webView, webViewParams)
        setContentView(layout)

        webView.webChromeClient = object : android.webkit.WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) {
                progressBar.progress = newProgress
                progressBar.visibility = if (newProgress == 100) android.view.View.GONE else android.view.View.VISIBLE
            }
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val requestUrl = request.url?.toString() ?: return false
                val scheme = request.url?.scheme ?: ""

                // Gdy GitHub (lub inny serwis) przekierowuje na custom scheme —
                // to jest OAuth callback. Otwórz go przez system (wróci do GitHub Mobile)
                // i zamknij tę aktywność.
                if (scheme != "http" && scheme != "https" && scheme != "about" && scheme != "data") {
                    android.util.Log.d("OAuthWebView", "OAuth callback: $requestUrl")
                    try {
                        val callbackIntent = Intent(Intent.ACTION_VIEW, Uri.parse(requestUrl)).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(callbackIntent)
                    } catch (e: Exception) {
                        android.util.Log.e("OAuthWebView", "Nie można otworzyć callback URL: $requestUrl", e)
                    }
                    finish()
                    return true
                }

                return false // pozwól WebView załadować normalnie
            }
        }

        android.util.Log.d("OAuthWebView", "Ładuję OAuth URL: $url")
        webView.loadUrl(url)
    }

    override fun onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        webView.destroy()
        super.onDestroy()
    }
}