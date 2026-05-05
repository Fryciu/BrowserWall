package com.example.browserfocus

import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "app/shortcuts"
    private val SCHEME_CHANNEL = "app/custom_scheme"
    private var initialUrl: String? = null
    private var pendingUrl: String? = null
    private var methodChannel: MethodChannel? = null
    private var schemeChannel: MethodChannel? = null
    private var pendingShortcutResult: MethodChannel.Result? = null
    private val REQUEST_CREATE_SHORTCUT = 1001

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Jeśli intent to OAuth flow innej aplikacji, przekaż do OAuthWebViewActivity
        if (isOAuthIntent(intent)) {
            forwardToOAuthActivity(intent)
            finish()
            return
        }
        initialUrl = extractUrl(intent)
        android.util.Log.d("SHORTCUT", "onCreate initialUrl = $initialUrl")
        android.util.Log.d("CustomScheme", "🚀 onCreate — startWebViewWatcher będzie wywołany z configureFlutterEngine")
    }

    override fun onResume() {
        super.onResume()
        android.util.Log.d("CustomScheme", "🔄 onResume — restartuje watcher")
        startWebViewWatcher()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Jeśli intent to OAuth flow innej aplikacji, przekaż do OAuthWebViewActivity
        if (isOAuthIntent(intent)) {
            forwardToOAuthActivity(intent)
            return
        }
        val url = extractUrl(intent) ?: return
        android.util.Log.d("SHORTCUT", "onNewIntent url=$url")
        initialUrl = url
        pendingUrl = url

        val channel = methodChannel
        android.util.Log.d("SHORTCUT", "methodChannel is ${if (channel != null) "READY" else "NULL"}")
        if (channel != null) {
            android.os.Handler(mainLooper).postDelayed({
                val pending = pendingUrl
                if (pending != null) {
                    pendingUrl = null
                    android.util.Log.d("SHORTCUT", "Wysyłam onShortcutUrl (delayed): $pending")
                    channel.invokeMethod("onShortcutUrl", pending)
                }
            }, 300)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CHANNEL
        )
        methodChannel = channel

        schemeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, SCHEME_CHANNEL
        )
        schemeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "openExternalUrl" -> {
                    val url = call.arguments as? String
                    result.success(url?.let { openExternalUrl(it) } ?: false)
                }
                "openUrlInPackage" -> {
                    val args = call.arguments as? Map<*, *>
                    val url = args?.get("url") as? String
                    val packageName = args?.get("package") as? String
                    result.success(
                        if (url != null && packageName != null) {
                            openUrlInPackage(url, packageName)
                        } else {
                            false
                        }
                    )
                }
                else -> result.notImplemented()
            }
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialUrl" -> {
                    val url = pendingUrl ?: initialUrl
                    pendingUrl = null
                    android.util.Log.d("SHORTCUT", "getInitialUrl -> $url")
                    result.success(url)
                }
                "createShortcut" -> {
                    val name = call.argument<String>("name") ?: "Skrót"
                    val url = call.argument<String>("url") ?: ""
                    createHomeScreenShortcut(name, url, result)
                }
                else -> result.notImplemented()
            }
        }

        pendingUrl?.let { url ->
            pendingUrl = null
            android.util.Log.d("SHORTCUT", "Wysyłam buforowany URL: $url")
            channel.invokeMethod("onShortcutUrl", url)
        }

        // Uruchom polling który szuka WebView i owija je interceptorem
        startWebViewWatcher()
    }

    /**
     * Co 500ms szuka nowych WebView w hierarchii widoków i owija je interceptorem.
     * Zatrzymuje się po 30 sekundach (60 prób).
     */
    private fun startWebViewWatcher() {
        val handler = android.os.Handler(mainLooper)
        var attempts = 0
        val runnable = object : Runnable {
            override fun run() {
                attempts++
                val rootView = window?.decorView as? ViewGroup
                android.util.Log.d("CustomScheme", "Poll #$attempts rootView=${rootView?.childCount} children")
                if (rootView != null) {
                    findAndWrapWebViews(rootView)
                }
                if (attempts < 60) {
                    handler.postDelayed(this, 500)
                }
            }
        }
        handler.postDelayed(runnable, 500)
    }

    private fun findAndWrapWebViews(viewGroup: ViewGroup, depth: Int = 0) {
        for (i in 0 until viewGroup.childCount) {
            val child = viewGroup.getChildAt(i) ?: continue
            // InAppWebView dziedziczy po WebView ale szukamy po obu
            val webView: WebView? = when {
                child is WebView -> child
                child.javaClass.name.contains("InAppWebView") -> child as? WebView
                else -> null
            }
            if (webView != null) {
                val id = System.identityHashCode(webView)
                if (webView.webViewClient !is ExternalAppWebViewClient) {
                    wrapWebView(webView)
                    android.util.Log.d("CustomScheme", "Wrapped WebView (${child.javaClass.simpleName}): $id")
                }
            } else if (child is ViewGroup) {
                findAndWrapWebViews(child, depth + 1)
            }
        }
    }

    private fun wrapWebView(webView: WebView) {
        val originalClient = webView.webViewClient
        webView.webViewClient = ExternalAppWebViewClient(originalClient)
    }

    private inner class ExternalAppWebViewClient(
        private val originalClient: WebViewClient
    ) : WebViewClient() {
        override fun shouldOverrideUrlLoading(
            view: WebView,
            request: android.webkit.WebResourceRequest
        ): Boolean {
            val url = request.url?.toString() ?: return originalClient.shouldOverrideUrlLoading(view, request)
            val scheme = request.url?.scheme ?: ""
            if (isCustomScheme(scheme)) {
                android.util.Log.d("CustomScheme", "shouldOverride: $url")
                if (!openExternalUrl(url)) {
                    schemeChannel?.invokeMethod("onCustomScheme", url)
                }
                return true
            }
            return originalClient.shouldOverrideUrlLoading(view, request)
        }

        override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
            if (url != null) {
                val scheme = android.net.Uri.parse(url).scheme ?: ""
                if (isCustomScheme(scheme)) {
                    android.util.Log.d("CustomScheme", "onPageStarted: $url")
                    if (!openExternalUrl(url)) {
                        schemeChannel?.invokeMethod("onCustomScheme", url)
                    }
                    view.stopLoading()
                    return
                }
            }
            originalClient.onPageStarted(view, url, favicon)
        }

        override fun onPageFinished(view: WebView, url: String?) =
            originalClient.onPageFinished(view, url)

        override fun onReceivedError(
            view: WebView,
            request: android.webkit.WebResourceRequest,
            error: android.webkit.WebResourceError
        ) {
            val url = request.url?.toString()
            val scheme = request.url?.scheme ?: ""
            if (url != null && request.isForMainFrame && isCustomScheme(scheme)) {
                android.util.Log.d("CustomScheme", "onReceivedError: $url error=${error.description}")
                if (!openExternalUrl(url)) {
                    schemeChannel?.invokeMethod("onCustomScheme", url)
                }
                view.stopLoading()
                return
            }
            originalClient.onReceivedError(view, request, error)
        }

        override fun onReceivedHttpError(view: WebView, request: android.webkit.WebResourceRequest, errorResponse: android.webkit.WebResourceResponse) =
            originalClient.onReceivedHttpError(view, request, errorResponse)

        override fun shouldInterceptRequest(view: WebView, request: android.webkit.WebResourceRequest) =
            originalClient.shouldInterceptRequest(view, request)

        override fun onLoadResource(view: WebView, url: String?) =
            originalClient.onLoadResource(view, url)

        override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) =
            originalClient.doUpdateVisitedHistory(view, url, isReload)

        override fun onReceivedSslError(view: WebView, handler: android.webkit.SslErrorHandler?, error: android.net.http.SslError?) =
            originalClient.onReceivedSslError(view, handler, error)

        override fun onScaleChanged(view: WebView, oldScale: Float, newScale: Float) =
            originalClient.onScaleChanged(view, oldScale, newScale)
    }

    private fun isCustomScheme(scheme: String): Boolean {
        return scheme.isNotEmpty() &&
            scheme != "http" &&
            scheme != "https" &&
            scheme != "about" &&
            scheme != "file" &&
            scheme != "data" &&
            scheme != "javascript" &&
            scheme != "blob"
    }

    private fun openExternalUrl(url: String): Boolean {
        return try {
            val intent = buildExternalIntent(url)
            android.util.Log.d("CustomScheme", "openExternalUrl: $url package=${intent.`package`}")
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            val packageName = Uri.parse(url).host?.takeIf { it.contains('.') }
            if (!packageName.isNullOrBlank()) {
                try {
                    val packageIntent = buildExternalIntent(url).setPackage(packageName)
                    android.util.Log.d("CustomScheme", "retry package=$packageName url=$url")
                    startActivity(packageIntent)
                    true
                } catch (packageError: ActivityNotFoundException) {
                    openFallbackUrl(url)
                } catch (packageError: Exception) {
                    android.util.Log.e("CustomScheme", "Cannot open package URL: $url", packageError)
                    openFallbackUrl(url)
                }
            } else openFallbackUrl(url)
        } catch (e: Exception) {
            android.util.Log.e("CustomScheme", "Cannot open external URL: $url", e)
            false
        }
    }

    private fun buildExternalIntent(url: String): Intent {
        return if (url.startsWith("intent://", ignoreCase = true)) {
            Intent.parseUri(url, Intent.URI_INTENT_SCHEME).apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
                component = null
                selector = null
            }
        } else {
            Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
            }
        }
    }

    private fun openUrlInPackage(url: String, packageName: String): Boolean {
        return try {
            val intent = buildExternalIntent(url).apply {
                setPackage(packageName)
            }
            android.util.Log.d("CustomScheme", "openUrlInPackage package=$packageName url=$url")
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            android.util.Log.w("CustomScheme", "Package cannot open URL: package=$packageName url=$url")
            false
        } catch (e: Exception) {
            android.util.Log.e("CustomScheme", "Cannot open URL in package: package=$packageName url=$url", e)
            false
        }
    }

    private fun openFallbackUrl(url: String): Boolean {
        val fallback = runCatching {
            Intent.parseUri(url, Intent.URI_INTENT_SCHEME)
                .getStringExtra("browser_fallback_url")
        }.getOrNull()

        return if (!fallback.isNullOrBlank()) {
            try {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(fallback)))
                true
            } catch (fallbackError: Exception) {
                android.util.Log.e("CustomScheme", "Cannot open fallback URL: $fallback", fallbackError)
                false
            }
        } else {
            android.util.Log.w("CustomScheme", "No activity for external URL: $url")
            false
        }
    }

    private fun isOAuthIntent(intent: Intent?): Boolean {
        if (intent == null) return false
        val data = intent.data ?: return false
        val redirectUri = data.getQueryParameter("redirect_uri") ?: return false
        val redirectScheme = runCatching { Uri.parse(redirectUri).scheme ?: "" }.getOrElse { "" }
        val isOAuth = redirectScheme.isNotEmpty()
            && redirectScheme != "http"
            && redirectScheme != "https"
            && redirectScheme != "myapp"
            && redirectScheme != "my-app"
        if (isOAuth) {
            android.util.Log.d("OAuthWebView", "Wykryto OAuth intent: redirect_uri scheme=$redirectScheme url=${data}")
        }
        return isOAuth
    }

    private fun forwardToOAuthActivity(intent: Intent) {
        val data = intent.data ?: return
        android.util.Log.d("OAuthWebView", "Przekazuję do OAuthWebViewActivity: $data")
        val oauthIntent = Intent(this, OAuthWebViewActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            setData(data)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        startActivity(oauthIntent)
    }

    private fun extractUrl(intent: Intent?): String? {
        if (intent == null) return null
        val extraUrl = intent.getStringExtra("shortcut_url")
        if (extraUrl != null) return extraUrl
        val data: Uri? = intent.data
        if (data != null) {
            if (data.scheme == "myapp") {
                return data.getQueryParameter("url")
            }
            return data.toString()
        }
        return null
    }

    private fun createHomeScreenShortcut(name: String, url: String, result: MethodChannel.Result) {
        try {
            val shortcutIntent = Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse(url)
                putExtra("shortcut_url", url)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val sm = getSystemService(ShortcutManager::class.java)
                if (sm != null && sm.isRequestPinShortcutSupported) {
                    val shortcut = ShortcutInfo.Builder(this, "sc_${System.currentTimeMillis()}")
                        .setShortLabel(name.take(25))
                        .setLongLabel(name)
                        .setIcon(Icon.createWithResource(this, R.mipmap.launcher_icon))
                        .setIntent(shortcutIntent)
                        .build()
                    sm.requestPinShortcut(shortcut, null)
                    android.util.Log.d("SHORTCUT", "ShortcutManager OK")
                    result.success(null)
                    return
                }
            }

            android.util.Log.d("SHORTCUT", "Próbuję ACTION_CREATE_SHORTCUT")
            val bitmap = getBitmapFromResource(R.mipmap.launcher_icon)

            val extras = Intent().apply {
                putExtra(Intent.EXTRA_SHORTCUT_INTENT, shortcutIntent)
                putExtra(Intent.EXTRA_SHORTCUT_NAME, name)
                if (bitmap != null) {
                    putExtra(Intent.EXTRA_SHORTCUT_ICON, bitmap)
                } else {
                    putExtra(
                        Intent.EXTRA_SHORTCUT_ICON_RESOURCE,
                        Intent.ShortcutIconResource.fromContext(this@MainActivity, R.mipmap.launcher_icon)
                    )
                }
            }

            val createIntent = Intent(Intent.ACTION_CREATE_SHORTCUT).apply {
                putExtras(extras)
            }

            if (createIntent.resolveActivity(packageManager) != null) {
                pendingShortcutResult = result
                @Suppress("DEPRECATION")
                startActivityForResult(createIntent, REQUEST_CREATE_SHORTCUT)
                android.util.Log.d("SHORTCUT", "startActivityForResult wysłane")
            } else {
                android.util.Log.w("SHORTCUT", "ACTION_CREATE_SHORTCUT niedostępne, próbuję broadcast")
                @Suppress("DEPRECATION")
                sendBroadcast(Intent("com.android.launcher.action.INSTALL_SHORTCUT").apply {
                    putExtras(extras)
                    putExtra("duplicate", false)
                })
                result.success(null)
            }
        } catch (e: Exception) {
            android.util.Log.e("SHORTCUT", "Błąd: ${e.message}", e)
            result.error("SHORTCUT_ERROR", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CREATE_SHORTCUT) {
            android.util.Log.d("SHORTCUT", "onActivityResult resultCode=$resultCode data=$data extras=${data?.extras?.keySet()}")
            if (resultCode == RESULT_OK && data != null) {
                @Suppress("DEPRECATION")
                sendBroadcast(Intent("com.android.launcher.action.INSTALL_SHORTCUT").apply {
                    putExtras(data)
                    putExtra("duplicate", false)
                })
                android.util.Log.d("SHORTCUT", "Skrót zainstalowany przez launcher (RESULT_OK)")
            } else if (data != null && data.extras != null) {
                @Suppress("DEPRECATION")
                sendBroadcast(Intent("com.android.launcher.action.INSTALL_SHORTCUT").apply {
                    putExtras(data)
                    putExtra("duplicate", false)
                })
                android.util.Log.d("SHORTCUT", "Skrót zainstalowany przez launcher (resultCode=$resultCode)")
            } else {
                android.util.Log.w("SHORTCUT", "Launcher nie zwrócił danych skrótu, próbuję fallback broadcast")
                pendingShortcutResult?.error("SHORTCUT_CANCELLED", "Anulowano lub launcher nie obsługuje", null)
                pendingShortcutResult = null
                return
            }
            pendingShortcutResult?.success(null)
            pendingShortcutResult = null
        }
    }

    private fun getBitmapFromResource(resId: Int): android.graphics.Bitmap? {
        return try {
            val drawable = androidx.core.content.res.ResourcesCompat.getDrawable(
                resources, resId, theme
            ) ?: return null
            val bitmap = android.graphics.Bitmap.createBitmap(
                drawable.intrinsicWidth.takeIf { it > 0 } ?: 96,
                drawable.intrinsicHeight.takeIf { it > 0 } ?: 96,
                android.graphics.Bitmap.Config.ARGB_8888
            )
            val canvas = android.graphics.Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bitmap
        } catch (e: Exception) {
            android.util.Log.e("SHORTCUT", "Błąd bitmap: ${e.message}")
            null
        }
    }
}