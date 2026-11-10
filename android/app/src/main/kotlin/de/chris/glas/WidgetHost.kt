package de.chris.glas

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.SizeF
import android.view.Gravity
import android.view.View
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlin.math.ceil
import kotlin.math.max

/**
 * Hosts the widgets of other apps, as every Android launcher does. Android asks the user once
 * whether Glas may show widgets; after that a widget is bound to an id, which Flutter shows
 * through the platform view [VIEW_TYPE].
 */
class WidgetHost(private val activity: Activity, messenger: BinaryMessenger) {
    private val manager = AppWidgetManager.getInstance(activity)
    private val host = AppWidgetHost(activity, HOST_ID)
    private val channel = MethodChannel(messenger, "glas/widgets")
    private val main = Handler(Looper.getMainLooper())
    private val workers = Executors.newSingleThreadExecutor()

    /** The widget being added while Android's consent or the widget's own setup is open. */
    private var pending: MethodChannel.Result? = null
    private var pendingId = AppWidgetManager.INVALID_APPWIDGET_ID

    val factory: PlatformViewFactory = object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val params = args as? Map<*, *>
            val view = widgetView(
                (params?.get("id") as? Number)?.toInt() ?: AppWidgetManager.INVALID_APPWIDGET_ID,
                (params?.get("width") as? Number)?.toFloat() ?: 0f,
                (params?.get("height") as? Number)?.toFloat() ?: 0f,
            )
            return object : PlatformView {
                override fun getView() = view
                override fun dispose() {}
            }
        }
    }

    init {
        channel.setMethodCallHandler(::handle)
    }

    /** Widgets only update while the host listens. */
    fun start() {
        try {
            host.startListening()
        } catch (e: RuntimeException) {
            // The widget service can be busy right after boot; the next start tries again.
        }
    }

    fun stop() {
        try {
            host.stopListening()
        } catch (e: RuntimeException) {
            // Nothing to stop.
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        workers.shutdown()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "providers" -> result.success(providers())
            "preview" -> {
                val info = find(call.arguments as? String)
                workers.execute {
                    val png = info?.let { runCatching { preview(it) }.getOrNull() }
                    main.post { result.success(png) }
                }
            }
            "bind" -> bind(call.arguments as? String, result)
            "delete" -> {
                (call.arguments as? Number)?.let { host.deleteAppWidgetId(it.toInt()) }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun installed(): List<AppWidgetProviderInfo> = try {
        manager.getInstalledProvidersForProfile(Process.myUserHandle())
    } catch (e: RuntimeException) {
        emptyList()
    }

    private fun find(provider: String?) = installed().firstOrNull { it.provider.flattenToString() == provider }

    private fun providers(): List<Map<String, Any?>> {
        val packages = activity.packageManager
        val density = activity.resources.displayMetrics.density
        return installed().map { info ->
            val wide = info.resizeMode and AppWidgetProviderInfo.RESIZE_HORIZONTAL != 0
            val tall = info.resizeMode and AppWidgetProviderInfo.RESIZE_VERTICAL != 0
            val app = runCatching {
                packages.getApplicationLabel(packages.getApplicationInfo(info.provider.packageName, 0)).toString()
            }.getOrNull()
            mapOf(
                "provider" to info.provider.flattenToString(),
                "package" to info.provider.packageName,
                "label" to info.loadLabel(packages),
                "app" to (app ?: info.loadLabel(packages)),
                // The size the widget wants, and the smallest it can take, in launcher cells.
                "cellsX" to cells(info.minWidth / density, if (Build.VERSION.SDK_INT >= 31) info.targetCellWidth else 0),
                "cellsY" to cells(info.minHeight / density, if (Build.VERSION.SDK_INT >= 31) info.targetCellHeight else 0),
                "minCellsX" to (if (wide && info.minResizeWidth > 0) cells(info.minResizeWidth / density, 0) else null),
                "minCellsY" to (if (tall && info.minResizeHeight > 0) cells(info.minResizeHeight / density, 0) else null),
            )
        }
    }

    /** Android's rule of thumb: n cells are 70 n - 30 dp. */
    private fun cells(dp: Float, target: Int) = if (target > 0) target else max(1, ceil((dp + 30) / 70).toInt())

    private fun preview(info: AppWidgetProviderInfo): ByteArray? {
        val drawable = info.loadPreviewImage(activity, 0) ?: info.loadIcon(activity, 0) ?: return null
        val scale = PREVIEW_PX.toFloat() / max(1, max(drawable.intrinsicWidth, drawable.intrinsicHeight))
        val width = max(1, (drawable.intrinsicWidth * scale).toInt())
        val height = max(1, (drawable.intrinsicHeight * scale).toInt())
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, width, height)
        drawable.draw(Canvas(bitmap))
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    private fun bind(provider: String?, result: MethodChannel.Result) {
        val info = find(provider)
        if (info == null || pending != null) return result.success(null)
        pending = result
        pendingId = host.allocateAppWidgetId()
        if (manager.bindAppWidgetIdIfAllowed(pendingId, info.provider)) return configure()
        // Not allowed yet: Android asks the user, once for all widgets if they tick the box.
        val ask = Intent(AppWidgetManager.ACTION_APPWIDGET_BIND)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, pendingId)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, info.provider)
        try {
            activity.startActivityForResult(ask, REQUEST_BIND)
        } catch (e: RuntimeException) {
            finish(false)
        }
    }

    /** Widgets that need choices first, like which list to show, bring their own screen. */
    private fun configure() {
        val info = manager.getAppWidgetInfo(pendingId) ?: return finish(false)
        val optional = Build.VERSION.SDK_INT >= 31 &&
            info.widgetFeatures and AppWidgetProviderInfo.WIDGET_FEATURE_CONFIGURATION_OPTIONAL != 0
        if (info.configure == null || optional) return finish(true)
        try {
            host.startAppWidgetConfigureActivityForResult(activity, pendingId, 0, REQUEST_CONFIGURE, null)
        } catch (e: RuntimeException) {
            finish(false)
        }
    }

    private fun finish(ok: Boolean) {
        val result = pending ?: return
        pending = null
        if (ok) {
            result.success(pendingId)
        } else {
            host.deleteAppWidgetId(pendingId)
            result.success(null)
        }
    }

    /** True when the result belonged to a widget being added. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        when (requestCode) {
            REQUEST_BIND -> if (resultCode == Activity.RESULT_OK) configure() else finish(false)
            REQUEST_CONFIGURE -> finish(resultCode == Activity.RESULT_OK)
            else -> return false
        }
        return true
    }

    /** [width] and [height] are the widget's place on the home screen in dp. */
    private fun widgetView(id: Int, width: Float, height: Float): View {
        val info = manager.getAppWidgetInfo(id) ?: return missing()
        return try {
            host.createView(activity, id, info).apply {
                setPadding(0, 0, 0, 0)
                if (width > 0 && height > 0) {
                    if (Build.VERSION.SDK_INT >= 31) {
                        updateAppWidgetSize(Bundle(), listOf(SizeF(width, height)))
                    } else {
                        @Suppress("DEPRECATION")
                        updateAppWidgetSize(Bundle(), width.toInt(), height.toInt(), width.toInt(), height.toInt())
                    }
                }
            }
        } catch (e: RuntimeException) {
            missing()
        }
    }

    /** Stands in for a widget whose app was removed or whose binding was lost with a reinstall. */
    private fun missing(): View = TextView(activity).apply {
        text = "Widget nicht verfügbar"
        gravity = Gravity.CENTER
        textSize = 13f
        setTextColor(Color.WHITE)
        setBackgroundColor(0x33000000)
    }

    companion object {
        const val VIEW_TYPE = "glas/appwidget"
        private const val HOST_ID = 1024
        private const val REQUEST_BIND = 51
        private const val REQUEST_CONFIGURE = 52
        private const val PREVIEW_PX = 480
    }
}
