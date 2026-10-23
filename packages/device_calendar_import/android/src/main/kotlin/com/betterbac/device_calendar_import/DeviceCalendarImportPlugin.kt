// Read-only access to the device's calendars (Google Calendar and any other
// account synced to Android's calendar provider) for BetterBAC's calendar
// import. The Rust side (api/device_calendar.rs) decides what to keep.
package com.betterbac.device_calendar_import

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.Calendar
import java.util.TimeZone
import java.util.concurrent.Executors

class DeviceCalendarImportPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermission: MethodChannel.Result? = null
    private val worker = Executors.newSingleThreadExecutor()

    companion object {
        private const val PERMISSION_REQUEST = 4207
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "betterbac/device_calendar")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // --- ActivityAware (needed to show the permission prompt) ---------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    // --- Methods ------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasAccess" -> result.success(hasAccess())
            "requestAccess" -> requestAccess(result)
            "listCalendars" -> runInBackground(result) { if (hasAccess()) listCalendars() else emptyList() }
            "events" -> {
                val start = (call.argument<Number>("startMs"))?.toLong()
                val end = (call.argument<Number>("endMs"))?.toLong()
                val ids = call.argument<List<String>>("calendarIds") ?: emptyList()
                if (start == null || end == null || !hasAccess() || ids.isEmpty()) {
                    result.success(emptyList<Map<String, Any?>>())
                } else {
                    runInBackground(result) { events(start, end, ids) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun hasAccess(): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestAccess(result: MethodChannel.Result) {
        if (hasAccess()) return result.success(true)
        val activity: Activity = activityBinding?.activity ?: return result.success(false)
        if (pendingPermission != null) return result.error("busy", "Permission request already running", null)
        pendingPermission = result
        activity.requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        pendingPermission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        pendingPermission = null
        return true
    }

    /** Runs a content-provider query off the main thread, replying on it. */
    private fun runInBackground(result: MethodChannel.Result, work: () -> Any) {
        val main = android.os.Handler(android.os.Looper.getMainLooper())
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("calendar_error", e.message, null) }
            }
        }
    }

    private fun listCalendars(): List<Map<String, Any?>> {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.CALENDAR_COLOR,
        )
        val out = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI, projection, null, null, null,
        )?.use { c ->
            while (c.moveToNext()) {
                val title = c.getString(1) ?: ""
                val lower = title.lowercase()
                out.add(
                    mapOf(
                        "id" to c.getLong(0).toString(),
                        "title" to title,
                        "account" to (c.getString(2) ?: ""),
                        "color" to c.getInt(3),
                        // Birthdays and holiday calendars start unticked.
                        "suggested" to !(lower.contains("birthday") || lower.contains("holiday")),
                    )
                )
            }
        }
        return out
    }

    private fun events(start: Long, end: Long, calendarIds: List<String>): List<Map<String, Any?>> {
        // Instances expands recurring events into individual occurrences.
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, start)
            ContentUris.appendId(it, end)
        }.build()
        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.CALENDAR_ID,
            CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.DESCRIPTION,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
        )
        val placeholders = calendarIds.joinToString(",") { "?" }
        val out = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            uri,
            projection,
            "${CalendarContract.Instances.CALENDAR_ID} IN ($placeholders)",
            calendarIds.toTypedArray(),
            "${CalendarContract.Instances.BEGIN} ASC",
        )?.use { c ->
            while (c.moveToNext()) {
                val allDay = c.getInt(7) == 1
                var begin = c.getLong(5)
                var finish = if (c.isNull(6)) null else c.getLong(6)
                if (allDay) {
                    // Android stores all-day events at UTC midnight; BetterBAC
                    // (and Apple) use local midnight.
                    begin = utcDayToLocalMidnight(begin)
                    finish = finish?.let(::utcDayToLocalMidnight)
                }
                out.add(
                    mapOf(
                        // One id per occurrence: recurring events share an event id.
                        "id" to "${c.getLong(0)}@${c.getLong(5)}",
                        "calendarId" to c.getLong(1).toString(),
                        "calendarTitle" to (c.getString(2) ?: ""),
                        "title" to (c.getString(3) ?: ""),
                        "notes" to (c.getString(4) ?: ""),
                        "startMs" to begin,
                        "endMs" to finish,
                        "allDay" to allDay,
                    )
                )
            }
        }
        return out
    }

    private fun utcDayToLocalMidnight(utcMs: Long): Long {
        val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { timeInMillis = utcMs }
        return Calendar.getInstance().apply {
            clear()
            set(utc.get(Calendar.YEAR), utc.get(Calendar.MONTH), utc.get(Calendar.DAY_OF_MONTH))
        }.timeInMillis
    }
}
