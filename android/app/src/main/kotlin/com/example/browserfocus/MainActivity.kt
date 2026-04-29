package com.example.browserfocus

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "app/shortcuts"
    private var initialUrl: String? = null
    // Bufor na URL które przyszły przed gotowością Flutter engine
    private var pendingUrl: String? = null
    private var methodChannel: MethodChannel? = null
    private var pendingShortcutResult: MethodChannel.Result? = null
    private val REQUEST_CREATE_SHORTCUT = 1001

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initialUrl = extractUrl(intent)
        android.util.Log.d("SHORTCUT", "onCreate initialUrl = $initialUrl")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val url = extractUrl(intent) ?: return
        android.util.Log.d("SHORTCUT", "onNewIntent url=$url")
        initialUrl = url

        val channel = methodChannel
        if (channel != null) {
            // Engine gotowy — wyślij od razu
            channel.invokeMethod("onShortcutUrl", url)
        } else {
            // Engine nie gotowy — zapamiętaj do wysłania później
            pendingUrl = url
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CHANNEL
        )
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialUrl" -> {
                    // Zwróć pendingUrl jeśli jest, fallback na initialUrl
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

        // Wyślij buforowany URL jeśli przyszedł przed gotowością engine
        pendingUrl?.let { url ->
            pendingUrl = null
            android.util.Log.d("SHORTCUT", "Wysyłam buforowany URL: $url")
            channel.invokeMethod("onShortcutUrl", url)
        }
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

            // Metoda 1: ShortcutManager API (Android 8+, nie działa na Vivo)
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

            // Metoda 2: ACTION_CREATE_SHORTCUT — działa na Vivo
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
                // result.success wywoła onActivityResult
            } else {
                // Metoda 3: ostateczny fallback broadcast
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
                // Niektóre launchery zwracają dane ale z innym resultCode
                @Suppress("DEPRECATION")
                sendBroadcast(Intent("com.android.launcher.action.INSTALL_SHORTCUT").apply {
                    putExtras(data)
                    putExtra("duplicate", false)
                })
                android.util.Log.d("SHORTCUT", "Skrót zainstalowany przez launcher (resultCode=$resultCode)")
            } else {
                android.util.Log.w("SHORTCUT", "Launcher nie zwrócił danych skrótu, próbuję fallback broadcast")
                // Ostateczny fallback — wyślij oryginalny intent bezpośrednio
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