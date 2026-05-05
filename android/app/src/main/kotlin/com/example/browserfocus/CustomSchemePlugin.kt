package com.example.browserfocus

import android.content.Context
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Plugin który rejestruje się w flutter_inappwebview i przechwytuje
 * custom scheme redirecty (np. github://) na poziomie natywnego WebViewClient.
 *
 * flutter_inappwebview rejestruje swój WebViewClient przez PlatformWebViewCreationParams.
 * Nie możemy go bezpośrednio podmienić, ale możemy użyć refleksji żeby owinąć go
 * w nasz dekorator który przechwytuje shouldOverrideUrlLoading PRZED pluginem.
 */
object CustomSchemeInterceptor {

    private const val CHANNEL = "app/custom_scheme"
    private var methodChannel: MethodChannel? = null

    fun register(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )
    }

    /**
     * Wywołaj tę metodę po tym jak flutter_inappwebview stworzy WebView.
     * Wstrzykuje nasz WebViewClient jako dekorator.
     */
    fun wrapWebView(webView: WebView) {
        val originalClient = webView.webViewClient
        webView.webViewClient = InterceptingWebViewClient(originalClient, methodChannel)
    }

    private class InterceptingWebViewClient(
        private val delegate: WebViewClient,
        private val channel: MethodChannel?
    ) : WebViewClient() {

        override fun shouldOverrideUrlLoading(
            view: WebView,
            request: WebResourceRequest
        ): Boolean {
            val url = request.url?.toString() ?: return delegate.shouldOverrideUrlLoading(view, request)

            // Jeśli to custom scheme (nie http/https/about/file/data) — przechwytujemy
            val scheme = request.url?.scheme ?: ""
            if (scheme != "http" && scheme != "https" &&
                scheme != "about" && scheme != "file" &&
                scheme != "data" && scheme != "javascript" &&
                scheme != "blob" && scheme.isNotEmpty()
            ) {
                android.util.Log.d("CustomScheme", "Przechwycono custom scheme: $url")
                channel?.invokeMethod("onCustomScheme", url)
                return true // Blokuj WebView przed próbą załadowania
            }

            return delegate.shouldOverrideUrlLoading(view, request)
        }

        override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
            // Sprawdź URL też tutaj — dla niektórych redirectów
            if (url != null) {
                val uri = android.net.Uri.parse(url)
                val scheme = uri.scheme ?: ""
                if (scheme != "http" && scheme != "https" &&
                    scheme != "about" && scheme != "file" &&
                    scheme != "data" && scheme != "javascript" &&
                    scheme != "blob" && scheme.isNotEmpty()
                ) {
                    android.util.Log.d("CustomScheme", "onPageStarted custom scheme: $url")
                    channel?.invokeMethod("onCustomScheme", url)
                    view.stopLoading()
                    return
                }
            }
            delegate.onPageStarted(view, url, favicon)
        }

        override fun onPageFinished(view: WebView, url: String?) =
            delegate.onPageFinished(view, url)

        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest,
            error: android.webkit.WebResourceError
        ) = delegate.onReceivedError(view, request, error)

        override fun onReceivedHttpError(
            view: WebView,
            request: WebResourceRequest,
            errorResponse: android.webkit.WebResourceResponse
        ) = delegate.onReceivedHttpError(view, request, errorResponse)

        override fun shouldInterceptRequest(
            view: WebView,
            request: WebResourceRequest
        ) = delegate.shouldInterceptRequest(view, request)

        override fun onLoadResource(view: WebView, url: String?) =
            delegate.onLoadResource(view, url)

        override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) =
            delegate.doUpdateVisitedHistory(view, url, isReload)

        override fun onFormResubmission(view: WebView, dontResend: android.os.Message?, resend: android.os.Message?) =
            delegate.onFormResubmission(view, dontResend, resend)

        override fun onReceivedSslError(view: WebView, handler: android.webkit.SslErrorHandler?, error: android.net.http.SslError?) =
            delegate.onReceivedSslError(view, handler, error)

        override fun onScaleChanged(view: WebView, oldScale: Float, newScale: Float) =
            delegate.onScaleChanged(view, oldScale, newScale)
    }
}