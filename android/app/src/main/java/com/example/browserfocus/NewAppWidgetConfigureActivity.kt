package com.example.browserfocus

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.EditText

class NewAppWidgetConfigureActivity : Activity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        setContentView(R.layout.new_app_widget_configure)

        appWidgetId =
                intent?.extras?.getInt(
                        AppWidgetManager.EXTRA_APPWIDGET_ID,
                        AppWidgetManager.INVALID_APPWIDGET_ID
                )
                        ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        // Pobierz URL i nazwę przekazane przez pinAppWidget lub staging prefs
        val prefs = getSharedPreferences(NewAppWidget.PREFS_NAME, Context.MODE_PRIVATE)
        val stagedUrl = prefs.getString(NewAppWidget.STAGED_URL_KEY, "") ?: ""
        val stagedName = prefs.getString(NewAppWidget.STAGED_NAME_KEY, "") ?: ""

        val nameInput = findViewById<EditText>(R.id.appwidget_text)
        nameInput.setText(stagedName)

        val addButton = findViewById<Button>(R.id.add_button)
        addButton.setOnClickListener {
            val name = nameInput.text.toString().trim().ifEmpty { stagedName.ifEmpty { "Skrót" } }
            val url = stagedUrl.ifEmpty { "https://www.google.com" }

            // Zapisz pod prawdziwym ID widżetu
            prefs.edit()
                    .putString(NewAppWidget.prefKeyName(appWidgetId), name)
                    .putString(NewAppWidget.prefKeyUrl(appWidgetId), url)
                    .remove(NewAppWidget.STAGED_URL_KEY)
                    .remove(NewAppWidget.STAGED_NAME_KEY)
                    .apply()

            val appWidgetManager = AppWidgetManager.getInstance(this)
            NewAppWidget.updateAppWidget(this, appWidgetManager, appWidgetId)

            val resultValue = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            setResult(RESULT_OK, resultValue)
            finish()
        }
    }
}
