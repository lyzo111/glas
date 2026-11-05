package de.chris.glas

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.LocationManager
import android.provider.CalendarContract
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale
import kotlin.concurrent.thread
import kotlin.math.roundToInt

/** Data for the widgets. Nothing but the rounded position ever leaves the phone. */
object CalendarAndWeather {
    private const val REFRESH_MS = 30 * 60 * 1000L
    private var fetching = false

    fun events(context: Context): List<Map<String, Any?>> {
        if (context.checkSelfPermission(Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) return emptyList()
        val now = System.currentTimeMillis()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            android.content.ContentUris.appendId(it, now)
            android.content.ContentUris.appendId(it, now + 7 * 24 * 3600 * 1000L)
        }.build()
        val columns = arrayOf(
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.DISPLAY_COLOR,
        )
        val result = mutableListOf<Map<String, Any?>>()
        runCatching {
            context.contentResolver.query(uri, columns, null, null, "${CalendarContract.Instances.BEGIN} ASC")?.use {
                while (it.moveToNext() && result.size < 5) {
                    result += mapOf(
                        "title" to (it.getString(0) ?: "Ereignis"),
                        "begin" to it.getLong(1),
                        "allDay" to (it.getInt(2) == 1),
                        "color" to it.getInt(3),
                    )
                }
            }
        }
        return result
    }

    /** Returns the cached forecast and renews it in the background once it is old. */
    fun weather(context: Context): Map<String, Any?>? {
        val prefs = context.getSharedPreferences("glas", Context.MODE_PRIVATE)
        val cached = prefs.getString("forecast", null)
        if (System.currentTimeMillis() - prefs.getLong("forecastTime", 0) > REFRESH_MS) fetch(context)
        return cached?.let { runCatching { parse(JSONObject(it), prefs.getString("weatherCity", "") ?: "") }.getOrNull() }
    }

    private fun fetch(context: Context) {
        if (fetching) return
        if (context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) return
        val locations = context.getSystemService(LocationManager::class.java)
        val location = locations.getProviders(true).mapNotNull {
            runCatching { locations.getLastKnownLocation(it) }.getOrNull()
        }.maxByOrNull { it.time } ?: return
        fetching = true
        thread {
            runCatching {
                val lat = "%.2f".format(Locale.US, location.latitude)
                val lon = "%.2f".format(Locale.US, location.longitude)
                val url = URL(
                    "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon" +
                        "&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code" +
                        "&daily=temperature_2m_max,temperature_2m_min,weather_code&forecast_days=6&timezone=auto",
                )
                val connection = url.openConnection() as HttpURLConnection
                connection.connectTimeout = 10_000
                connection.readTimeout = 10_000
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                @Suppress("DEPRECATION")
                val city = runCatching {
                    Geocoder(context, Locale.GERMAN).getFromLocation(location.latitude, location.longitude, 1)
                        ?.firstOrNull()?.locality
                }.getOrNull() ?: ""
                context.getSharedPreferences("glas", Context.MODE_PRIVATE).edit()
                    .putString("forecast", body)
                    .putString("weatherCity", city)
                    .putLong("forecastTime", System.currentTimeMillis())
                    .apply()
                Bridge.notifyAll("changed")
            }
            fetching = false
        }
    }

    private fun parse(json: JSONObject, city: String): Map<String, Any?> {
        val current = json.getJSONObject("current")
        val daily = json.getJSONObject("daily")
        val hourly = json.getJSONObject("hourly")
        val times = hourly.getJSONArray("time")
        val temperatures = hourly.getJSONArray("temperature_2m")
        val codes = hourly.getJSONArray("weather_code")
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm", Locale.US)
        val hourAgo = System.currentTimeMillis() - 3600 * 1000L
        val hours = (0 until times.length()).mapNotNull { i ->
            val time = format.parse(times.getString(i))?.time ?: return@mapNotNull null
            if (time < hourAgo) return@mapNotNull null
            mapOf("time" to time, "temperature" to temperatures.getDouble(i).roundToInt(), "code" to codes.getInt(i))
        }.take(6)
        val dates = daily.getJSONArray("time")
        val dayFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val days = (0 until dates.length()).mapNotNull { i ->
            val time = dayFormat.parse(dates.getString(i))?.time ?: return@mapNotNull null
            mapOf(
                "time" to time,
                "code" to daily.getJSONArray("weather_code").getInt(i),
                "high" to daily.getJSONArray("temperature_2m_max").getDouble(i).roundToInt(),
                "low" to daily.getJSONArray("temperature_2m_min").getDouble(i).roundToInt(),
            )
        }
        return mapOf(
            "city" to city,
            "temperature" to current.getDouble("temperature_2m").roundToInt(),
            "code" to current.getInt("weather_code"),
            "day" to (current.getInt("is_day") == 1),
            "high" to daily.getJSONArray("temperature_2m_max").getDouble(0).roundToInt(),
            "low" to daily.getJSONArray("temperature_2m_min").getDouble(0).roundToInt(),
            "hours" to hours,
            "days" to days,
        )
    }
}
