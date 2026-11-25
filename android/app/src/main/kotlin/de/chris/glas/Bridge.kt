package de.chris.glas

import android.Manifest
import android.app.Activity
import android.app.ActivityOptions
import android.app.WallpaperManager
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.LauncherActivityInfo
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.Drawable
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraManager


import android.media.AudioManager
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.os.UserHandle
import android.provider.MediaStore
import android.provider.Settings
import android.provider.Telephony
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import android.util.DisplayMetrics
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/** Everything Dart needs from Android, shared by the home and lock screens. */
/** Icons are drawn this large; the biggest one on screen is about 215 pixels wide. */
private const val ICON_PX = 288

class Bridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val onUnlock: () -> Unit = {},
) {
    private val channel = MethodChannel(messenger, "glas/native")
    private val apps = activity.getSystemService(LauncherApps::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null
    private var torchOn = false

    private val appChanges = object : LauncherApps.Callback() {
        override fun onPackageRemoved(packageName: String, user: UserHandle) = notifyDart("apps")
        // An update can bring a new icon, so Dart has to drop the one it holds for these packages.
        override fun onPackageAdded(packageName: String, user: UserHandle) = appsUpdated(listOf(packageName))
        override fun onPackageChanged(packageName: String, user: UserHandle) = appsUpdated(listOf(packageName))
        override fun onPackagesAvailable(names: Array<out String>, user: UserHandle, replacing: Boolean) = appsUpdated(names.toList())
        override fun onPackagesUnavailable(names: Array<out String>, user: UserHandle, replacing: Boolean) = notifyDart("apps")
    }

        /** Headphones coming and going show in the island. */
    private val audioDevices = object : android.media.AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out android.media.AudioDeviceInfo>) = notifyDart("changed")
        override fun onAudioDevicesRemoved(removed: Array<out android.media.AudioDeviceInfo>) = notifyDart("changed")
    }

    /** Plugging in, the ringer switch and Do Not Disturb show in the island at once. */
    private val power = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = notifyDart("changed")
    }

    private val torch = object : CameraManager.TorchCallback() {
        override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
            torchOn = enabled
        }
    }

    init {
        channel.setMethodCallHandler(::handle)
        apps.registerCallback(appChanges, main)
        activity.getSystemService(CameraManager::class.java).registerTorchCallback(torch, main)
                activity.getSystemService(AudioManager::class.java).registerAudioDeviceCallback(audioDevices, main)
        activity.registerReceiver(
            power,
            IntentFilter().apply {
                addAction(Intent.ACTION_POWER_CONNECTED)
                                addAction(Intent.ACTION_POWER_DISCONNECTED)
                addAction(AudioManager.RINGER_MODE_CHANGED_ACTION)
                addAction(android.app.NotificationManager.ACTION_INTERRUPTION_FILTER_CHANGED)
            },
        )
        bridges.add(this)
    }

    fun close() {
        stopTilt()
        bridges.remove(this)
        apps.unregisterCallback(appChanges)
        activity.getSystemService(CameraManager::class.java).unregisterTorchCallback(torch)
                runCatching { activity.unregisterReceiver(power) }
        activity.getSystemService(AudioManager::class.java).unregisterAudioDeviceCallback(audioDevices)
        channel.setMethodCallHandler(null)
    }

    private var tiltWanted = false
    private var tiltOn = false
    private var lastTilt = 0L
    private val tiltListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val now = SystemClock.uptimeMillis()
            if (now - lastTilt < TILT_INTERVAL_MS) return
            lastTilt = now
            channel.invokeMethod("tilt", listOf(-event.values[0].toDouble(), event.values[1].toDouble()))
        }

        override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) = Unit
    }

    /** Gravity drives the wallpaper's perspective shift; only while the home screen shows. */
    fun startTilt() {
        if (!tiltWanted || tiltOn) return
        val sensors = activity.getSystemService(SensorManager::class.java)
        val gravity = sensors.getDefaultSensor(Sensor.TYPE_GRAVITY) ?: return
        tiltOn = sensors.registerListener(tiltListener, gravity, SensorManager.SENSOR_DELAY_GAME, main)
    }

    fun stopTilt() {
        if (!tiltOn) return
        activity.getSystemService(SensorManager::class.java).unregisterListener(tiltListener)
        tiltOn = false
    }

    fun notifyDart(event: String) {
        main.post { channel.invokeMethod(event, null) }
    }

    private fun appsUpdated(packages: List<String>) {
        main.post { channel.invokeMethod("appsUpdated", packages) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val notifications = NotificationService.instance
        when (call.method) {
            "apps" -> result.success(listApps())
            "icon" -> iconWorkers.execute {
                val bytes = runCatching {
                    iconPng(call.argument("package")!!, call.argument("activity")!!, call.argument("layer") ?: "plain")
                }.getOrNull()
                main.post { result.success(bytes) }
            }
            "launch" -> {
                launch(call)
                result.success(null)
            }
            "uninstall" -> {
                activity.startActivity(Intent(Intent.ACTION_DELETE, Uri.parse("package:${call.arguments}")))
                result.success(null)
            }
            "appInfo" -> {
                activity.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${call.arguments}")),
                )
                result.success(null)
            }
            "shortcuts" -> result.success(shortcuts(call.arguments as String))
            "startShortcut" -> {
                runCatching {
                    apps.startShortcut(call.argument("package")!!, call.argument("id")!!, null, null, Process.myUserHandle())
                }
                result.success(null)
            }
            "status" -> result.success(status())
            "permissions" -> result.success(permissions())
            "requestHome" -> {
                requestHome()
                result.success(null)
            }
            "openPermission" -> {
                openPermission(call.arguments as String)
                result.success(null)
            }
            "panel" -> {
                openPanel(call.arguments as String)
                result.success(null)
            }
            "torch" -> {
                setTorch(call.arguments as Boolean)
                result.success(null)
            }
            "volume" -> {
                val audio = activity.getSystemService(AudioManager::class.java)
                val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                audio.setStreamVolume(AudioManager.STREAM_MUSIC, ((call.arguments as Double) * max).toInt(), 0)
                result.success(null)
            }
            "brightness" -> {
                if (Settings.System.canWrite(activity)) {
                    Settings.System.putInt(
                        activity.contentResolver,
                        Settings.System.SCREEN_BRIGHTNESS,
                        ((call.arguments as Double) * 255).toInt().coerceIn(1, 255),
                    )
                }
                result.success(null)
            }
            "doNotDisturb" -> {
                notifications?.setDoNotDisturb(call.arguments as Boolean)
                result.success(null)
            }
            "notifications" -> result.success(notifications?.list(activity) ?: emptyList<Any>())
            "openNotification" -> {
                val key = call.arguments as String
                val open = { notifications?.open(key, activity); Unit }
                // Opening an app from the lock screen must go through the PIN first.
                (activity as? LockActivity)?.unlock(open) ?: open()
                result.success(null)
            }
            "replyNotification" -> {
                val send = { notifications?.reply(call.argument("key")!!, call.argument("text")!!); Unit }
                // The text waits for the PIN, so a locked phone can't send anything.
                (activity as? LockActivity)?.unlock(send) ?: send()
                result.success(null)
            }
            "dismissNotification" -> {
                notifications?.dismiss(call.arguments as String)
                result.success(null)
            }
            "media" -> result.success(media())
            "events" -> result.success(CalendarAndWeather.events(activity))
            "weather" -> result.success(CalendarAndWeather.weather(activity))
            "defaults" -> result.success(defaults())
            "dropStatusBar" -> {
                activity.dropStatusBar()
                result.success(null)
            }
            "openWeather" -> {
                openWeather()
                result.success(null)
            }
            "mediaAction" -> {
                mediaController()?.transportControls?.let {
                    when (call.arguments) {
                        "toggle" -> if (isPlaying(mediaController())) it.pause() else it.play()
                        "next" -> it.skipToNext()
                        "previous" -> it.skipToPrevious()
                    }
                }
                result.success(null)
            }
            "pickWallpaper" -> {
                pendingPick = result
                activity.startActivityForResult(
                    Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("image/*"),
                    PICK_IMAGE,
                )
            }
            "setWallpaper" -> Thread {
                val done = runCatching {
                    setWallpaper(call.argument("home")!!, WallpaperManager.FLAG_SYSTEM)
                    setWallpaper(call.argument("lock")!!, WallpaperManager.FLAG_LOCK)
                }.isSuccess
                main.post { result.success(done) }
            }.start()
            "setLockEnabled" -> {
                activity.getSharedPreferences("glas", Context.MODE_PRIVATE).edit()
                    .putBoolean("lockEnabled", call.arguments as Boolean).apply()
                result.success(null)
            }
            "showLock" -> {
                activity.startActivity(Intent(activity, LockActivity::class.java))
                result.success(null)
            }
            "unlock" -> {
                onUnlock()
                result.success(null)
            }
            "tilt" -> {
                tiltWanted = call.arguments as Boolean
                if (tiltWanted) startTilt() else stopTilt()
                result.success(null)
            }
                        "depthCutout" -> depthCutout(call.arguments as ByteArray, result)
                        "zones" -> result.success(
                WORLD.mapValues { java.time.ZoneId.of(it.value).rules.getOffset(java.time.Instant.now()).totalSeconds },
            )
            "photo" -> iconWorkers.execute {
                val bytes = runCatching { photo(call.arguments as Int) }.getOrNull()
                main.post { result.success(bytes) }
            }
            "control" -> {
                control(call.arguments as String)
                result.success(null)
            }
                        "settingsChanged" -> {
                notifyAll("changed")
                result.success(null)
            }
            "screenOff" -> result.success(ScreenOffService.turnOff())
            "lockShortcuts" -> result.success(lockShortcuts())
            "openLocked" -> {
                val open = { launch(call) }
                (activity as? LockActivity)?.unlock(open) ?: open()
                result.success(null)
            }
            "camera" -> {
                val lock = activity as? LockActivity
                val action = if (lock != null) MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA_SECURE else MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA
                // The secure camera sits on the keyguard, and this window would stay above it.
                runCatching { activity.startActivity(systemCamera(action)) }.onSuccess { lock?.leave() }
                result.success(null)
            }
            "webSearch" -> {
                val intent = Intent(Intent.ACTION_WEB_SEARCH).putExtra("query", call.arguments as String)
                try {
                    activity.startActivity(intent)
                } catch (_: ActivityNotFoundException) {
                    val url = "https://www.google.com/search?q=" + Uri.encode(call.arguments as String)
                    activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun listApps(): List<Map<String, Any?>> {
        val own = activity.packageName
        return apps.getActivityList(null, Process.myUserHandle()).filter { it.applicationInfo.packageName != own }.map {
            mapOf(
                "package" to it.applicationInfo.packageName,
                "activity" to it.componentName.className,
                "label" to it.label.toString(),
                "category" to category(it.applicationInfo),
                "installed" to it.firstInstallTime,
            )
        }
    }

    private fun category(info: ApplicationInfo) = when (info.category) {
        ApplicationInfo.CATEGORY_GAME -> "Spiele"
        ApplicationInfo.CATEGORY_AUDIO, ApplicationInfo.CATEGORY_VIDEO -> "Unterhaltung"
        ApplicationInfo.CATEGORY_IMAGE -> "Kreativität"
        ApplicationInfo.CATEGORY_SOCIAL -> "Soziale Netzwerke"
        ApplicationInfo.CATEGORY_NEWS -> "Nachrichten"
        ApplicationInfo.CATEGORY_MAPS -> "Reisen"
        ApplicationInfo.CATEGORY_PRODUCTIVITY -> "Produktivität"
        else -> if (info.flags and ApplicationInfo.FLAG_SYSTEM != 0) "Dienstprogramme" else "Sonstige"
    }

    private fun find(pkg: String, cls: String): LauncherActivityInfo? =
        apps.getActivityList(pkg, Process.myUserHandle()).firstOrNull { it.componentName.className == cls }

    /** Full-bleed square; Dart clips it to the rounded icon shape. */
    private fun iconPng(pkg: String, cls: String, layer: String): ByteArray? {
        val info = find(pkg, cls) ?: return null
        val size = ICON_PX
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        // The highest density there is: Glas draws icons larger than Android's launchers do.
        val icon: Drawable = info.getIcon(DisplayMetrics.DENSITY_XXXHIGH)
        var mask = layer == "mono"
        // How many pixels an icon without any transparency would cover.
        var area = size * size
        if (icon is AdaptiveIconDrawable) {
            // Adaptive layers are 108 units wide with the visible part in the middle 72.
            val extra = size / 4
            val monochrome = if (mask && Build.VERSION.SDK_INT >= 33) icon.monochrome?.mutate() else null
            monochrome?.setTint(Color.WHITE)
            if (monochrome != null) mask = false
            val layers = when {
                monochrome != null -> listOf(monochrome)
                layer == "plain" -> listOf(icon.background, icon.foreground)
                else -> listOf(icon.foreground)
            }
            for (drawable in layers) {
                drawable?.setBounds(-extra, -extra, size + extra, size + extra)
                drawable?.draw(canvas)
            }
        } else {
            if (layer == "plain") canvas.drawColor(Color.WHITE)
            val inset = size / 8
            icon.setBounds(inset, inset, size - inset, size - inset)
            icon.draw(canvas)
            area = (size - 2 * inset) * (size - 2 * inset)
        }
        if (mask) toMask(bitmap, area)
        return ByteArrayOutputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            it.toByteArray()
        }
    }

    private fun luma(pixel: Int) = (Color.red(pixel) * 54 + Color.green(pixel) * 183 + Color.blue(pixel) * 19) shr 8

    /**
     * Turns a drawn icon into white with its shape in the alpha channel, for the glass icon
     * styles, which colour it themselves. The edges keep their soft pixels that way. An app
     * without a monochrome layer gets one made from brightness: a glyph on a clear ground keeps
     * its outline, and of a picture that fills the icon, what stands out from its ground shows.
     */
    private fun toMask(bitmap: Bitmap, area: Int) {
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        val histogram = IntArray(256)
        var solid = 0
        for (pixel in pixels) {
            if (pixel ushr 24 < 128) continue
            histogram[luma(pixel)]++
            solid++
        }
        if (solid == 0) return
        fun percentile(share: Double): Int {
            var seen = 0
            for (value in 0..255) {
                seen += histogram[value]
                if (seen >= solid * share) return value
            }
            return 255
        }
        val low = percentile(0.02)
        val high = percentile(0.98)
        val ground = percentile(0.5)
        val full = solid > area * 0.72
        val spread = if (full) maxOf(high - ground, ground - low) else high - low
        for (i in pixels.indices) {
            val alpha = pixels[i] ushr 24
            val value = luma(pixels[i])
            val share = when {
                alpha == 0 -> 0f
                full && spread < 24 -> 0.3f
                full -> ((Math.abs(value - ground) / spread.toFloat() - 0.15f) / 0.85f).coerceIn(0f, 1f)
                spread < 40 -> 1f
                else -> 0.45f + 0.55f * ((value - low) / spread.toFloat()).coerceIn(0f, 1f)
            }
            pixels[i] = ((alpha * share).toInt() shl 24) or 0xFFFFFF
        }
        bitmap.setPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
    }

    /** The system's reveal animation grows the app out of its icon. */
    private fun launch(call: MethodCall) {
        val component = ComponentName(call.argument<String>("package")!!, call.argument<String>("activity")!!)
        val x = call.argument<Int>("x") ?: 0
        val y = call.argument<Int>("y") ?: 0
        val size = call.argument<Int>("size") ?: 0
        val options = ActivityOptions.makeScaleUpAnimation(activity.window.decorView, x, y, size, size).toBundle()
        runCatching {
            apps.startMainActivity(component, Process.myUserHandle(), Rect(x, y, x + size, y + size), options)
        }
    }

    private fun shortcuts(pkg: String): List<Map<String, String>> {
        if (!apps.hasShortcutHostPermission()) return emptyList()
        val query = LauncherApps.ShortcutQuery()
            .setPackage(pkg)
            .setQueryFlags(
                LauncherApps.ShortcutQuery.FLAG_MATCH_DYNAMIC or LauncherApps.ShortcutQuery.FLAG_MATCH_MANIFEST,
            )
        return runCatching { apps.getShortcuts(query, Process.myUserHandle()) }.getOrNull().orEmpty().take(4).map {
            mapOf("id" to it.id, "label" to (it.shortLabel ?: it.id).toString())
        }
    }

    private fun status(): Map<String, Any?> {
        val battery = activity.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, 0) ?: 0
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val plugged = (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
        val connectivity = activity.getSystemService(ConnectivityManager::class.java)
        val network = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
        val audio = activity.getSystemService(AudioManager::class.java)
        return mapOf(
            "battery" to level * 100 / scale,
            "charging" to plugged,
            "wifi" to (network?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true),
            "cellular" to (network?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true),
            "torch" to torchOn,
            "carrier" to activity.getSystemService(TelephonyManager::class.java).networkOperatorName,
            "doNotDisturb" to (NotificationService.instance?.isDoNotDisturb() == true),
            "volume" to audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() /
                audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
                        "brightness" to Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128) / 255.0,
                        "ringer" to audio.ringerMode,
            "rotationLocked" to (Settings.System.getInt(activity.contentResolver, Settings.System.ACCELEROMETER_ROTATION, 1) == 0),
            "headphones" to headphones(audio),
            "live" to NotificationService.instance?.live(),
        )
    }

    private fun headphones(audio: AudioManager): String? = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        .firstOrNull { it.type in HEADPHONES }
        ?.productName?.toString()?.takeIf { it.isNotBlank() }

    private fun permissions(): Map<String, Boolean> {
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = activity.packageManager.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)
        return mapOf(
            "home" to (resolved?.activityInfo?.packageName == activity.packageName),
            "notifications" to NotificationService.hasAccess(activity),
            "overlay" to Settings.canDrawOverlays(activity),
            "writeSettings" to Settings.System.canWrite(activity),
                        "screenOff" to ScreenOffService.isEnabled(activity),
            "photos" to (activity.checkSelfPermission(PHOTOS) == PackageManager.PERMISSION_GRANTED),
            "location" to (activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED),
            "calendar" to (activity.checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED),
        )
    }

    private fun requestHome() {
        val roles = activity.getSystemService(RoleManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && roles.isRoleAvailable(RoleManager.ROLE_HOME)) {
            activity.startActivityForResult(roles.createRequestRoleIntent(RoleManager.ROLE_HOME), REQUEST_HOME)
        } else {
            activity.startActivity(Intent(Settings.ACTION_HOME_SETTINGS))
        }
    }

    /**
     * One UI's two lock screen shortcuts as "camera", "torch", "none" or a package name. It
     * keeps them as {"leftShortcut": {"component": ..., "enable": ...}, "rightShortcut": ...}.
     */
    private fun lockShortcuts(): List<String> {
        val saved = runCatching { Settings.System.getString(activity.contentResolver, SAMSUNG_LOCK_SHORTCUTS) }
            .onFailure { Log.w("Glas", "lock shortcuts unreadable", it) }.getOrNull() ?: return emptyList()
        val json = runCatching { JSONObject(saved) }.getOrNull() ?: return emptyList()
        return listOf("leftShortcut", "rightShortcut").map { side ->
            val corner = json.optJSONObject(side)
            val component = corner?.optString("component").orEmpty().lowercase()
            when {
                corner == null || !corner.optBoolean("enable", true) || component.isBlank() -> "none"
                "camera" in component -> "camera"
                "flash" in component || "torch" in component -> "torch"
                else -> corner.optString("component").substringBefore('/')
            }
        }
    }

    /**
     * Other apps can claim the camera actions too. Android then asks which one to use, and that
     * prompt can't appear on the lock screen, so it falls back to the PIN.
     */
    private fun systemCamera(action: String): Intent {
        val intent = Intent(action)
        val camera = activity.packageManager.queryIntentActivities(intent, 0)
            .firstOrNull { it.activityInfo.applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM != 0 }
        camera?.let { intent.setClassName(it.activityInfo.packageName, it.activityInfo.name) }
        return intent
    }

        /** One of the recent photos for the photos widget, small enough to keep in memory. */
    private fun photo(seed: Int): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val images = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        activity.contentResolver.query(images, arrayOf(MediaStore.Images.Media._ID), null, null, "${MediaStore.Images.Media.DATE_ADDED} DESC")
            ?.use { cursor ->
                if (cursor.count == 0) return null
                cursor.moveToPosition(seed.mod(minOf(cursor.count, 300)))
                val uri = android.content.ContentUris.withAppendedId(images, cursor.getLong(0))
                val thumb = activity.contentResolver.loadThumbnail(uri, android.util.Size(720, 720), null)
                return ByteArrayOutputStream().use {
                    thumb.compress(Bitmap.CompressFormat.JPEG, 85, it)
                    it.toByteArray()
                }
            }
        return null
    }

    /** The extra Control Centre buttons that need Android: most open their settings page. */
    private fun control(name: String) {
        if (name == "rotation") {
            if (!Settings.System.canWrite(activity)) return openPermission("writeSettings")
            val auto = Settings.System.getInt(activity.contentResolver, Settings.System.ACCELEROMETER_ROTATION, 1)
            Settings.System.putInt(activity.contentResolver, Settings.System.ACCELEROMETER_ROTATION, if (auto == 1) 0 else 1)
            return
        }
        val intent = when (name) {
            "timer" -> Intent(android.provider.AlarmClock.ACTION_SHOW_TIMERS)
            "alarm" -> Intent(android.provider.AlarmClock.ACTION_SHOW_ALARMS)
            "location" -> Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            "nfc" -> Intent(Settings.ACTION_NFC_SETTINGS)
            "display" -> Intent(Settings.ACTION_DISPLAY_SETTINGS)
            "hotspot" -> Intent().setClassName("com.android.settings", "com.android.settings.TetherSettings")
            else -> Intent(Settings.ACTION_SETTINGS)
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { activity.startActivity(intent) }.onFailure {
            runCatching { activity.startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
    }

    /** Samsung Weather has no launcher icon, so it is opened through its own screen. */
    private fun openWeather() {
        val samsung = Intent(Intent.ACTION_MAIN).setClassName(SAMSUNG_WEATHER, SAMSUNG_WEATHER_SCREEN)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            activity.startActivity(samsung)
        } catch (_: Exception) {
            val search = Uri.parse("https://www.google.com/search?q=Wetter")
            runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW, search)) }
        }
    }

    /** Cropped to the screen as Glas shows it; Android would otherwise fit it its own way. */
        private fun setWallpaper(encoded: ByteArray, which: Int) {
        val screen = screenSized(encoded)
        WallpaperManager.getInstance(activity).setBitmap(screen, null, true, which)
        screen.recycle()
    }

    /** The picture cropped to the screen the way Glas draws it, covering it from the middle. */
    private fun screenSized(encoded: ByteArray): Bitmap {
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        activity.windowManager.defaultDisplay.getRealMetrics(metrics)
        val picture = BitmapFactory.decodeByteArray(encoded, 0, encoded.size)
        val screen = Bitmap.createBitmap(metrics.widthPixels, metrics.heightPixels, Bitmap.Config.ARGB_8888)
        val scale = maxOf(screen.width.toFloat() / picture.width, screen.height.toFloat() / picture.height)
        val left = (screen.width - picture.width * scale) / 2
        val top = (screen.height - picture.height * scale) / 2
        Canvas(screen).drawBitmap(
            picture,
            null,
            RectF(left, top, left + picture.width * scale, top + picture.height * scale),
            Paint(Paint.FILTER_BITMAP_FLAG),
        )
                picture.recycle()
        return screen
    }

    /**
     * iOS's depth effect: the subject of the lock wallpaper on a transparent, screen-sized
     * picture, so it lines up with the wallpaper below it. Answers with its path, "" when the
     * picture has no subject, or null when the model isn't there yet and it should be retried.
     */
    private fun depthCutout(encoded: ByteArray, result: MethodChannel.Result) {
        iconWorkers.execute {
            // The model arrives with Play services (see the manifest); until then this fails and
            // Glas asks again on the next change or start.
            val segmenter = runCatching {
                SubjectSegmentation.getClient(SubjectSegmenterOptions.Builder().enableForegroundBitmap().build())
            }.onFailure { Log.w("Glas", "depth segmenter unavailable", it) }.getOrNull()
            val done = { path: String? ->
                main.post { result.success(path) }
                segmenter?.close()
                Unit
            }
            val screen = runCatching { screenSized(encoded) }.getOrNull()
            if (segmenter == null || screen == null) return@execute done(null)
            segmenter.process(InputImage.fromBitmap(screen, 0))
                .addOnSuccessListener(iconWorkers) { found ->
                    done(found.foregroundBitmap?.let(::saveCutout) ?: "")
                }
                .addOnFailureListener(iconWorkers) {
                    Log.w("Glas", "depth segmentation failed", it)
                    done(null)
                }
        }
    }

        /** Each saved look keeps its own cut-out, so older ones stay. */
    private fun saveCutout(cutout: Bitmap): String {
        val file = File(activity.filesDir, "depth-${System.currentTimeMillis()}.png")
        file.outputStream().use { cutout.compress(Bitmap.CompressFormat.PNG, 100, it) }
        cutout.recycle()
        return file.path
    }


    private fun defaults(): Map<String, String> {
        val browser = Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com"))
        return listOfNotNull(
            activity.getSystemService(TelecomManager::class.java).defaultDialerPackage?.let { "phone" to it },
            Telephony.Sms.getDefaultSmsPackage(activity)?.let { "sms" to it },
            activity.packageManager.resolveActivity(browser, PackageManager.MATCH_DEFAULT_ONLY)
                ?.activityInfo?.packageName?.takeIf { it != "android" }?.let { "browser" to it },
        ).toMap()
    }

    private fun openPermission(name: String) {
        when (name) {
            "location" -> return activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION), REQUEST_RUNTIME)
                        "photos" -> return activity.requestPermissions(arrayOf(PHOTOS), REQUEST_RUNTIME)
            "calendar" -> return activity.requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR), REQUEST_RUNTIME)
        }
        val appUri = Uri.parse("package:${activity.packageName}")
        activity.startActivity(
            when (name) {
                "notifications" -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                "overlay" -> Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, appUri)
                "screenOff" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                else -> Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, appUri)
            },
        )
    }

    private fun openPanel(name: String) {
        val intent = when (name) {
            "wifi" -> if (Build.VERSION.SDK_INT >= 29) Intent(Settings.Panel.ACTION_WIFI) else Intent(Settings.ACTION_WIFI_SETTINGS)
            "internet" -> if (Build.VERSION.SDK_INT >= 29) Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY) else Intent(Settings.ACTION_WIRELESS_SETTINGS)
            "bluetooth" -> Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            "airplane" -> Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS)
            else -> Intent(Settings.ACTION_SETTINGS)
        }
        runCatching { activity.startActivity(intent) }
    }

    private fun setTorch(on: Boolean) {
        val cameras = activity.getSystemService(CameraManager::class.java)
        runCatching {
            val id = cameras.cameraIdList.first {
                cameras.getCameraCharacteristics(it)
                    .get(android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
            cameras.setTorchMode(id, on)
        }
    }

    private fun mediaController(): MediaController? {
        if (!NotificationService.hasAccess(activity)) return null
        return runCatching {
            activity.getSystemService(MediaSessionManager::class.java)
                .getActiveSessions(NotificationService.component(activity))
                .firstOrNull()
        }.getOrNull()
    }

    private fun isPlaying(controller: MediaController?) =
        controller?.playbackState?.state == PlaybackState.STATE_PLAYING

    private fun media(): Map<String, Any?>? {
        val controller = mediaController() ?: return null
        val metadata = controller.metadata ?: return null
        // Apps leave idle sessions behind that have nothing to show.
        val title = metadata.getString(android.media.MediaMetadata.METADATA_KEY_TITLE) ?: return null
        return mapOf(
            "title" to title,
            "artist" to metadata.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST),
                        "playing" to isPlaying(controller),
            "art" to art(metadata),
        )
    }

        /** A small copy of the cover for the island. */
    private fun art(metadata: android.media.MediaMetadata): ByteArray? {
        val cover = metadata.getBitmap(android.media.MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: metadata.getBitmap(android.media.MediaMetadata.METADATA_KEY_ART) ?: return null
        val small = Bitmap.createScaledBitmap(cover, 192, 192 * cover.height / maxOf(cover.width, 1), true)
        return ByteArrayOutputStream().use {
            small.compress(Bitmap.CompressFormat.PNG, 100, it)
            it.toByteArray()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_IMAGE) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) return result.success(null)
        Thread {
            val path = runCatching {
                val file = File(activity.filesDir, "wallpaper-${System.currentTimeMillis()}")
                activity.contentResolver.openInputStream(uri)!!.use { input ->
                    file.outputStream().use { input.copyTo(it) }
                }
                file.path
            }.getOrNull()
            main.post { result.success(path) }
        }.start()
    }

    companion object {
                        private const val TILT_INTERVAL_MS = 33L
        private val PHOTOS = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
        private val WORLD = linkedMapOf(
            "New York" to "America/New_York",
            "London" to "Europe/London",
            "Tokio" to "Asia/Tokyo",
            "Sydney" to "Australia/Sydney",
        )
        private val HEADPHONES = setOf(
            android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET,
            android.media.AudioDeviceInfo.TYPE_USB_HEADSET,
            26, // TYPE_BLE_HEADSET, Android 12
        )
        private const val PICK_IMAGE = 41
        private const val REQUEST_HOME = 42
        private const val REQUEST_RUNTIME = 43
        private const val SAMSUNG_LOCK_SHORTCUTS = "lock_application_shortcut"
        private const val SAMSUNG_WEATHER = "com.sec.android.daemonapp"
        private const val SAMSUNG_WEATHER_SCREEN = "com.samsung.android.weather.app.AppLauncherActivity"
        private val bridges = mutableSetOf<Bridge>()

        /// A new thread per icon would stall everything else when the App Library opens.
        private val iconWorkers = Executors.newFixedThreadPool(2)

        fun notifyAll(event: String) = bridges.toList().forEach { it.notifyDart(event) }
    }
}
