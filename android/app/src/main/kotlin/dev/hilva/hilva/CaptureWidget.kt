package dev.hilva.hilva
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
class CaptureWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val intent = Intent(context, MainActivity::class.java).setAction("dev.hilva.CAPTURE")
            val pending = PendingIntent.getActivity(context, 1, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val view = RemoteViews(context.packageName, R.layout.capture_widget)
            view.setOnClickPendingIntent(R.id.capture_button, pending)
            manager.updateAppWidget(id, view)
        }
    }
}
