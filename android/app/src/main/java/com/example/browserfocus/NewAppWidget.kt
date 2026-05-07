package com.example.browserfocus

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.widget.RemoteViews
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

class NewAppWidget : AppWidgetProvider() {

    override fun onUpdate(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        for (appWidgetId in appWidgetIds) {
            editor.remove(prefKeyName(appWidgetId))
            editor.remove(prefKeyUrl(appWidgetId))
        }
        editor.apply()
    }

    companion object {
        const val PREFS_NAME = "com.example.browserfocus.NewAppWidget"
        const val STAGED_NAME_KEY = "staged_widget_name"
        const val STAGED_URL_KEY = "staged_widget_url"

        // Executor żyje poza onUpdate — nie jest zabijany przez system
        private val executor = Executors.newCachedThreadPool()
        private val mainHandler = Handler(Looper.getMainLooper())

        fun prefKeyName(id: Int) = "widget_name_$id"
        fun prefKeyUrl(id: Int) = "widget_url_$id"

        fun updateAppWidget(
                context: Context,
                appWidgetManager: AppWidgetManager,
                appWidgetId: Int,
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val name = prefs.getString(prefKeyName(appWidgetId), "Skrót") ?: "Skrót"
            val url = prefs.getString(prefKeyUrl(appWidgetId), "") ?: ""

            val views = RemoteViews(context.packageName, R.layout.new_app_widget)
            views.setTextViewText(R.id.appwidget_text, name)
            views.setImageViewResource(R.id.browser_indicator_icon, R.mipmap.launcher_icon)

            // Intent otwierający przeglądarkę z zapisanym URL
            val launchIntent =
                    Intent(context, MainActivity::class.java).apply {
                        action = Intent.ACTION_VIEW
                        data = if (url.isNotEmpty()) Uri.parse(url) else null
                        putExtra("shortcut_url", url)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    }
            val pendingIntent =
                    PendingIntent.getActivity(
                            context,
                            appWidgetId,
                            launchIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                                            PendingIntent.FLAG_IMMUTABLE
                                    else 0
                    )
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)

            // Pokaż widżet od razu z domyślną ikoną
            appWidgetManager.updateAppWidget(appWidgetId, views)

            // Pobierz favicon na osobnym executorze — nie jest zabijany przez system
            if (url.isNotEmpty()) {
                executor.execute {
                    android.util.Log.d("NewAppWidget", "⏳ Pobieranie favicona dla: $url")
                    val bitmap = fetchFavicon(url)
                    if (bitmap != null) {
                        android.util.Log.d("NewAppWidget", "✅ Favicon pobrany")
                        views.setImageViewBitmap(R.id.appwidget_icon, bitmap)
                        appWidgetManager.updateAppWidget(appWidgetId, views)
                    } else {
                        android.util.Log.w("NewAppWidget", "❌ Brak favicona dla $url")
                    }
                }
            }
        }

        private fun fetchFavicon(url: String): android.graphics.Bitmap? {
            val domain = Uri.parse(url).host ?: return null
            val candidates =
                    listOf(
                            "https://$domain/favicon.ico",
                            "https://www.google.com/s2/favicons?domain=$domain&sz=128",
                            "https://icons.duckduckgo.com/ip3/$domain.ico",
                    )
            for (faviconUrl in candidates) {
                try {
                    android.util.Log.d("NewAppWidget", "🔍 Próba: $faviconUrl")
                    val conn = URL(faviconUrl).openConnection() as HttpURLConnection
                    conn.setRequestProperty(
                            "User-Agent",
                            "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36"
                    )
                    conn.connectTimeout = 8000
                    conn.readTimeout = 8000
                    conn.instanceFollowRedirects = true
                    conn.connect()
                    android.util.Log.d(
                            "NewAppWidget",
                            "📡 Response: ${conn.responseCode} dla $faviconUrl"
                    )
                    if (conn.responseCode == 200) {
                        val bmp = BitmapFactory.decodeStream(conn.inputStream)
                        conn.disconnect()
                        if (bmp != null) return bmp
                    }
                    conn.disconnect()
                } catch (e: Exception) {
                    android.util.Log.w("NewAppWidget", "❌ $faviconUrl — ${e.message}")
                }
            }
            return null
        }
    }
}
