package de.chris.glas

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent

/**
 * Turns the screen off on a double tap. Android offers an app no other way that leaves the
 * fingerprint working; device admin's lockNow would demand the PIN afterwards. The service
 * reads nothing: it subscribes to no real events and can't see window content.
 */
class ScreenOffService : AccessibilityService() {
    override fun onServiceConnected() {
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) = Unit

    override fun onInterrupt() = Unit

    companion object {
        private var instance: ScreenOffService? = null

        fun turnOff() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            instance?.performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN) == true

        /** The system stores either spelling of the component name. */
        fun isEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
            val own = ComponentName(context, ScreenOffService::class.java)
            return own.flattenToString() in enabled || own.flattenToShortString() in enabled
        }
    }
}
