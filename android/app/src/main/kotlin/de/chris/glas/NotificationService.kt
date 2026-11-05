package de.chris.glas

import android.app.Activity
import android.app.ActivityOptions
import android.app.Notification
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Source of badges and of the lock screen's notifications. Android keeps a granted listener
 * alive, so it also watches for the screen turning off without a permanent notification.
 */
class NotificationService : NotificationListenerService() {
    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = showLock(context)
    }

    override fun onListenerConnected() {
        instance = this
        registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
        Bridge.notifyAll("changed")
    }

    override fun onListenerDisconnected() {
        instance = null
        runCatching { unregisterReceiver(screenOff) }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) = Bridge.notifyAll("changed")

    override fun onNotificationRemoved(sbn: StatusBarNotification) = Bridge.notifyAll("changed")

    /** What the user would see in the shade: no group summaries, no ongoing status items. */
    private fun visible(): List<StatusBarNotification> = runCatching { activeNotifications.toList() }
        .getOrDefault(emptyList())
        .filter { it.isClearable && it.notification.flags and Notification.FLAG_GROUP_SUMMARY == 0 }

    fun list(context: Context): List<Map<String, Any?>> = visible().sortedByDescending { it.postTime }.map {
        val extras = it.notification.extras
        mapOf(
            "key" to it.key,
            "package" to it.packageName,
            "app" to runCatching {
                context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(it.packageName, 0))
                    .toString()
            }.getOrDefault(it.packageName),
            "title" to extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
            "text" to extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
                        "time" to it.postTime,
            "avatar" to images(context, it).first,
            "picture" to images(context, it).second,
            "canReply" to (replyAction(it.notification) != null),
        )
    }

    /**
     * Sent from the visible [activity]: a service is a background caller, and since Android 14
     * such a call runs but no longer brings the app to the front. A notification only goes
     * away if its app asked for that, or once the app was opened another way.
     */
    fun open(key: String, activity: Activity) {
                // Ongoing ones too: the island opens calls and timers, which can't be swiped away.
        val sbn = runCatching { activeNotifications.toList() }.getOrDefault(emptyList()).firstOrNull { it.key == key } ?: return
        val notification = sbn.notification
        val options = ActivityOptions.makeBasic()
        if (Build.VERSION.SDK_INT >= 34) {
            options.setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
        }
        val sent = runCatching {
            notification.contentIntent!!.send(activity, 0, null, null, null, null, options.toBundle())
        }.isSuccess
        if (!sent) {
            val launch = activity.packageManager.getLaunchIntentForPackage(sbn.packageName) ?: return
            runCatching { activity.startActivity(launch) }.onFailure { return }
        }
        if (notification.flags and Notification.FLAG_AUTO_CANCEL != 0) cancelNotification(key)
    }

    /** Messengers offer a text field in the shade; some only put it in their watch actions. */
    private fun replyAction(notification: Notification): Notification.Action? {
        val actions = notification.actions.orEmpty().toList() + Notification.WearableExtender(notification).actions
        val replies = actions.filter { action -> action.remoteInputs?.any { it.allowFreeFormInput } == true }
        return replies.firstOrNull { it.semanticAction == Notification.Action.SEMANTIC_ACTION_REPLY } ?: replies.firstOrNull()
    }

    /** Answers the way the shade's text field does, so the app sends the message itself. */
    fun reply(key: String, text: String) {
        val notification = visible().firstOrNull { it.key == key }?.notification ?: return
        val action = replyAction(notification) ?: return
        val inputs = action.remoteInputs
        val answers = Bundle().apply { inputs.filter { it.allowFreeFormInput }.forEach { putCharSequence(it.resultKey, text) } }
        val intent = Intent()
        RemoteInput.addResultsToIntent(inputs, intent, answers)
        RemoteInput.setResultsSource(intent, RemoteInput.SOURCE_FREE_FORM_INPUT)
        runCatching { action.actionIntent.send(this, 0, intent) }
    }

        /** A call or a running clock of another app, for the island; calls come first. */
    fun live(): Map<String, Any?>? {
        val running = runCatching { activeNotifications.toList() }.getOrDefault(emptyList()).filter {
            val n = it.notification
            it.isOngoing && (n.category == Notification.CATEGORY_CALL || n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        }
        val sbn = running.maxByOrNull { if (it.notification.category == Notification.CATEGORY_CALL) Long.MAX_VALUE else it.postTime } ?: return null
        val n = sbn.notification
        return mapOf(
            "key" to sbn.key,
            "package" to sbn.packageName,
            "title" to n.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
            "when" to n.`when`,
            "countDown" to n.extras.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN),
            "call" to (n.category == Notification.CATEGORY_CALL),
        )
    }

        /** Sender picture and attached image, made once per notification and kept. */
    private val pictures = HashMap<String, Pair<Long, Pair<ByteArray?, ByteArray?>>>()

    private fun images(context: Context, sbn: StatusBarNotification): Pair<ByteArray?, ByteArray?> {
        pictures[sbn.key]?.let { (time, made) -> if (time == sbn.postTime) return made }
        val n = sbn.notification
        val avatar = runCatching { n.getLargeIcon()?.loadDrawable(context)?.let { encode(it, 120, Bitmap.CompressFormat.PNG) } }.getOrNull()
        val picture = runCatching {
            @Suppress("DEPRECATION")
            (n.extras.getParcelable<Bitmap>(Notification.EXTRA_PICTURE))?.let { encode(BitmapDrawable(context.resources, it), 160, Bitmap.CompressFormat.JPEG) }
        }.getOrNull()
        if (pictures.size > 60) pictures.clear()
        return (avatar to picture).also { pictures[sbn.key] = sbn.postTime to it }
    }

    private fun encode(drawable: Drawable, size: Int, format: Bitmap.CompressFormat): ByteArray {
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val w = drawable.intrinsicWidth.coerceAtLeast(1)
        val h = drawable.intrinsicHeight.coerceAtLeast(1)
        val scale = maxOf(size.toFloat() / w, size.toFloat() / h)
        val dw = (w * scale).toInt()
        val dh = (h * scale).toInt()
        drawable.setBounds((size - dw) / 2, (size - dh) / 2, (size + dw) / 2, (size + dh) / 2)
        drawable.draw(android.graphics.Canvas(bitmap))
        return java.io.ByteArrayOutputStream().use {
            bitmap.compress(format, 85, it)
            bitmap.recycle()
            it.toByteArray()
        }
    }

    fun dismiss(key: String) = cancelNotification(key)

    fun setDoNotDisturb(on: Boolean) =
        requestInterruptionFilter(if (on) INTERRUPTION_FILTER_PRIORITY else INTERRUPTION_FILTER_ALL)

    fun isDoNotDisturb() = currentInterruptionFilter != INTERRUPTION_FILTER_ALL

    companion object {
        var instance: NotificationService? = null
            private set

        fun component(context: Context) = ComponentName(context, NotificationService::class.java)

        fun hasAccess(context: Context) =
            Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
                ?.contains(component(context).flattenToString()) == true

        fun showLock(context: Context) {
            val prefs = context.getSharedPreferences("glas", Context.MODE_PRIVATE)
            if (!prefs.getBoolean("lockEnabled", false) || !Settings.canDrawOverlays(context)) return
            val audio = context.getSystemService(AudioManager::class.java)
            if (audio.mode == AudioManager.MODE_IN_CALL || audio.mode == AudioManager.MODE_IN_COMMUNICATION) return
            context.startActivity(
                Intent(context, LockActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION),
            )
        }
    }
}
