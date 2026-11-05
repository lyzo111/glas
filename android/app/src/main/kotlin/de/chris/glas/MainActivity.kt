package de.chris.glas

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.io.File

/**
 * Glas draws its own status bar. Android's only appears briefly on a swipe from the edge and
 * goes away by itself, otherwise it would stay on top of Glas and swallow its touches.
 */
private fun Activity.hideStatusBar() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
    window.insetsController?.apply {
        systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        hide(WindowInsets.Type.statusBars())
    }
}

/**
 * A swipe from the top edge also brings up Android's bar, which then takes the next swipe for
 * a few seconds. Asking for it and hiding it again ends that at once.
 */
fun Activity.dropStatusBar() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
    window.insetsController?.show(WindowInsets.Type.statusBars())
    window.decorView.postDelayed({ hideStatusBar() }, STATUS_BAR_DROP_MS)
}

private const val STATUS_BAR_DROP_MS = 60L
private const val HOME_SETTLE_MS = 800L

/** Asks for the display's fastest mode; Android otherwise keeps a launcher at 60 Hz. */
private fun Activity.useFastestDisplayMode() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
    val current = display?.mode ?: return
    val fastest = display?.supportedModes
        ?.filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
        ?.maxByOrNull { it.refreshRate } ?: return
    window.attributes = window.attributes.apply { preferredDisplayModeId = fastest.modeId }
}

class MainActivity : FlutterActivity() {
    private var bridge: Bridge? = null
    private var resumedAt = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        useFastestDisplayMode()
        // Pictures of other apps left by the former app switcher.
        File(cacheDir, "previews").deleteRecursively()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideStatusBar()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = Bridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    /**
     * Pressing Home while already home closes folders, search and edit mode and returns to the
     * first page. Android sends the same intent when coming back from an app, so it only counts
     * once Glas has been on screen for a moment. Android pauses an activity to deliver an intent,
     * so window focus is what tells that it was in front.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val settled = hasWindowFocus() && SystemClock.uptimeMillis() - resumedAt > HOME_SETTLE_MS
        if (settled && intent.hasCategory(Intent.CATEGORY_HOME)) bridge?.notifyDart("home")
    }

    override fun onResume() {
        super.onResume()
        resumedAt = SystemClock.uptimeMillis()
        bridge?.notifyDart("changed")
        bridge?.startTilt()
    }

    override fun onPause() {
        bridge?.stopTilt()
        super.onPause()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        bridge?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        bridge?.notifyDart("changed")
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bridge?.close()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

/**
 * Lock screen in front of the keyguard. Finishing it never bypasses anything: on a secured
 * phone [unlock] hands over to the system's PIN or fingerprint prompt.
 */
class LockActivity : FlutterActivity() {
    private var bridge: Bridge? = null

    override fun getDartEntrypointFunctionName() = "lockMain"

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideStatusBar()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        setShowWhenLocked(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = Bridge(this, flutterEngine.dartExecutor.binaryMessenger) { unlock() }
    }

        override fun onResume() {
        super.onResume()
        bridge?.notifyDart("changed")
        bridge?.startTilt()
    }

    override fun onPause() {
        bridge?.stopTilt()
        super.onPause()
    }

    /** [then] runs once the phone really is unlocked. */
    fun unlock(then: () -> Unit = {}) {
        val keyguard = getSystemService(KeyguardManager::class.java)
        if (!keyguard.isKeyguardLocked) {
            then()
            return leave()
        }
        keyguard.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
            override fun onDismissSucceeded() {
                then()
                leave()
            }

            override fun onDismissCancelled() = leave()
            override fun onDismissError() = leave()
        })
        // SystemUI drops the PIN prompt again while this window covers the keyguard. Whatever
        // happens next, the keyguard stays in charge: nothing here can unlock the phone.
        setShowWhenLocked(false)
    }

    /**
     * Goes behind everything instead of finishing: the next screen-off then only brings this
     * window back, while a new one would start blank and be seen when the phone wakes up.
     */
    fun leave() {
        moveTaskToBack(true)
        setShowWhenLocked(true)
        @Suppress("DEPRECATION")
        overridePendingTransition(0, android.R.anim.fade_out)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bridge?.close()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
