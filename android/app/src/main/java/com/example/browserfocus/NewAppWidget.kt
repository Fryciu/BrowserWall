package com.example.browserfocus

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.widget.RemoteViews
import java.net.URL
import kotlin.concurrent.thread

/**
 * Widget skrótu do strony.
 * Wyświetla favikonę strony oraz stałą ikonę aplikacji z assets.
 */
class NewAppWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            deleteTitlePref(context, appWidgetId)
            deleteUrlPref(context, appWidgetId)
        }
    }
}

// ── Aktualizacja widgetu ───────────────────────────────────────────────────

internal fun updateAppWidget(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int
) {
    val widgetText = loadTitlePref(context, appWidgetId)
    val widgetUrl  = loadUrlPref(context, appWidgetId)

    val views = RemoteViews(context.packageName, R.layout.new_app_widget)
    views.setTextViewText(R.id.appwidget_text, widgetText)

    // 1. Ładowanie stałego znaczka "B" z assets/icon.png
    try {
        context.assets.open("icon.png").use { inputStream ->
            val indicatorBitmap = BitmapFactory.decodeStream(inputStream)
            views.setImageViewBitmap(R.id.browser_indicator_icon, indicatorBitmap)
        }
    } catch (e: Exception) {
        e.printStackTrace()
        // Jeśli pliku nie ma w assets, ImageView pozostanie puste
    }

    // 2. Intent otwierający MainActivity
    val launchIntent = Intent(context, MainActivity::class.java).apply {
        action = Intent.ACTION_VIEW
        putExtra("shortcut_url", widgetUrl)
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
    }

    val pendingIntent = PendingIntent.getActivity(
        context,
        appWidgetId,
        launchIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    // Ustawiamy kliknięcie na cały kontener (id musi zgadzać się z XML)
    views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)

    // 3. Pobieranie dynamicznej favikony strony w tle
    thread {
        try {
            if (widgetUrl.isNotEmpty()) {
                // Parametr sz=128 zapewnia dobrą jakość bez ucinania
                val faviconUrl = "https://www.google.com/s2/favicons?sz=128&domain=$widgetUrl"
                val connection = URL(faviconUrl).openConnection()
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
                
                val inputStream = connection.getInputStream()
                val bitmap = BitmapFactory.decodeStream(inputStream)

                if (bitmap != null) {
                    views.setImageViewBitmap(R.id.appwidget_icon, bitmap)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            // W razie błędu pozostanie domyślna ikona ustawiona w XML (src)
        }
        
        // Finalna aktualizacja (po załadowaniu obrazka z sieci)
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}

// ── Klucze SharedPreferences ───────────────────────────────────────────────

private const val PREFS_NAME  = "com.example.browserfocus.NewAppWidget"
private const val PREF_PREFIX_KEY = "appwidget_"
private const val PREF_URL_PREFIX = "appwidget_url_"

fun saveTitlePref(context: Context, appWidgetId: Int, text: String) {
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit().putString(PREF_PREFIX_KEY + appWidgetId, text).apply()
}

fun loadTitlePref(context: Context, appWidgetId: Int): String =
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getString(PREF_PREFIX_KEY + appWidgetId, "Skrót") ?: "Skrót"

fun deleteTitlePref(context: Context, appWidgetId: Int) {
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit().remove(PREF_PREFIX_KEY + appWidgetId).apply()
}

fun saveUrlPref(context: Context, appWidgetId: Int, url: String) {
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit().putString(PREF_URL_PREFIX + appWidgetId, url).apply()
}

fun loadUrlPref(context: Context, appWidgetId: Int): String =
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getString(PREF_URL_PREFIX + appWidgetId, "") ?: ""

fun deleteUrlPref(context: Context, appWidgetId: Int) {
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit().remove(PREF_URL_PREFIX + appWidgetId).apply()
}