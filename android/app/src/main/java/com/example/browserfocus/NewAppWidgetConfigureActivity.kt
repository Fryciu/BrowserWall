package com.example.browserfocus

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.widget.*

/**
 * Aktywność konfiguracyjna widgetu.
 *
 * Wywoływana AUTOMATYCZNIE przez Androida gdy użytkownik wybiera
 * "Dodaj skrót do ekranu głównego" (widget z galerii widgetów).
 *
 * Zadeklaruj ją w AndroidManifest.xml:
 *
 *   <activity android:name=".NewAppWidgetConfigureActivity"
 *       android:exported="false">
 *     <intent-filter>
 *       <action android:name="android.appwidget.action.APPWIDGET_CONFIGURE"/>
 *     </intent-filter>
 *   </activity>
 *
 * I w res/xml/new_app_widget_info.xml dodaj:
 *   android:configure="com.example.browserfocus.NewAppWidgetConfigureActivity"
 */
class NewAppWidgetConfigureActivity : Activity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Domyślny wynik = CANCELED (jeśli użytkownik cofnie się)
        setResult(RESULT_CANCELED)

        // Pobierz ID widgetu z intentu
        appWidgetId = intent.extras
            ?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        // ── Prosty layout zbudowany kodem (możesz zastąpić XML) ──────────
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 48, 48, 48)
        }

        val titleLabel = TextView(this).apply { text = "Nazwa skrótu:" }
        val nameField  = EditText(this).apply { hint = "np. YouTube" }

        val urlLabel = TextView(this).apply {
            text = "Adres strony (URL):"
            setPadding(0, 24, 0, 0)
        }
        val urlField = EditText(this).apply {
            hint = "https://..."
            inputType = android.text.InputType.TYPE_TEXT_VARIATION_URI
        }

        val addButton = Button(this).apply {
            text = "Dodaj skrót"
            setOnClickListener {
                val name = nameField.text.toString().trim()
                val url  = urlField.text.toString().trim()

                if (name.isEmpty()) {
                    nameField.error = "Podaj nazwę"
                    return@setOnClickListener
                }
                if (url.isEmpty() || (!url.startsWith("http://") && !url.startsWith("https://"))) {
                    urlField.error = "Podaj poprawny URL (https://...)"
                    return@setOnClickListener
                }

                // Zapisz dane w SharedPreferences
                saveTitlePref(this@NewAppWidgetConfigureActivity, appWidgetId, name)
                saveUrlPref(this@NewAppWidgetConfigureActivity, appWidgetId, url)

                // Zaktualizuj widget na ekranie głównym
                val appWidgetManager = AppWidgetManager.getInstance(this@NewAppWidgetConfigureActivity)
                updateAppWidget(this@NewAppWidgetConfigureActivity, appWidgetManager, appWidgetId)

                // Zwróć OK – widget zostaje dodany
                val resultValue = Intent().apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                }
                setResult(RESULT_OK, resultValue)
                finish()
            }
        }

        layout.addView(titleLabel)
        layout.addView(nameField)
        layout.addView(urlLabel)
        layout.addView(urlField)
        layout.addView(addButton)

        setContentView(layout)
    }
}