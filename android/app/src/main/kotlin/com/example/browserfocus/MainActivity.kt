package com.example.browserfocus

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.URLEncoder

class MainActivity : FlutterActivity() {
    private val CHANNEL = "app/shortcuts"
    private var initialUrl: String? = null


    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Obsłuż zarówno skróty myapp:// jak i zwykłe https://
        initialUrl = extractUrl(intent)
        android.util.Log.d("SHORTCUT", "onCreate initialUrl = $initialUrl")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val url = extractUrl(intent)
        android.util.Log.d("SHORTCUT", "onNewIntent url=$url")
        if (url != null) {
            initialUrl = url
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("onShortcutUrl", url)
            }
        }
    }

    // Nowa pomocnicza funkcja — obsługuje oba formaty
    private fun extractUrl(intent: Intent?): String? {
        if (intent == null) return null
        
        // Format skrótu: myapp://shortcut?url=https://...
        if (intent.data?.scheme == "myapp") {
            return intent.data?.getQueryParameter("url")
        }
        
        // Format zewnętrznego linku: ACTION_VIEW z https://
        if (intent.action == Intent.ACTION_VIEW) {
            val uri = intent.data
            if (uri != null && (uri.scheme == "http" || uri.scheme == "https")) {
                return uri.toString()
            }
        }
        
        return null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialUrl" -> result.success(initialUrl)
                    "createShortcut" -> {
                        val name = call.argument<String>("name") ?: ""
                        val url = call.argument<String>("url") ?: ""
                        val success = createHomeScreenShortcut(name, url)
                        if (success) result.success(null)
                        else result.error("SHORTCUT_ERROR", "Launcher nie obsługuje skrótów", null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun createHomeScreenShortcut(name: String, url: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            // Android 7 i starsze — stary broadcast
            val shortcutIntent = Intent(
                Intent.ACTION_VIEW,
                android.net.Uri.parse("myapp://shortcut?url=${URLEncoder.encode(url, "UTF-8")}")
            ).apply {
                setClass(this@MainActivity, MainActivity::class.java)
            }
            val addIntent = Intent("com.android.launcher.action.INSTALL_SHORTCUT").apply {
                putExtra(Intent.EXTRA_SHORTCUT_INTENT, shortcutIntent)
                putExtra(Intent.EXTRA_SHORTCUT_NAME, name)
                putExtra(
                    Intent.EXTRA_SHORTCUT_ICON_RESOURCE,
                    Intent.ShortcutIconResource.fromContext(this@MainActivity, R.mipmap.ic_launcher)
                )
            }
            sendBroadcast(addIntent)
            return true
        }

        // Android 8+ — ShortcutManager
        val shortcutManager = getSystemService(ShortcutManager::class.java) ?: return false

        if (!shortcutManager.isRequestPinShortcutSupported) return false

        val shortcutIntent = Intent(
            Intent.ACTION_VIEW,
            android.net.Uri.parse("myapp://shortcut?url=${URLEncoder.encode(url, "UTF-8")}")
        ).apply {
            setClass(this@MainActivity, MainActivity::class.java)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        val shortcut = ShortcutInfo.Builder(this, "shortcut_${System.currentTimeMillis()}")
            .setShortLabel(name)
            .setLongLabel(name)
            .setIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
            .setIntent(shortcutIntent)
            .build()

        // Callback gdy użytkownik potwierdzi dodanie
        val callbackIntent = shortcutManager.createShortcutResultIntent(shortcut)
        val successCallback = PendingIntent.getBroadcast(
            this, 0, callbackIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        shortcutManager.requestPinShortcut(shortcut, successCallback.intentSender)
        return true
    }
}