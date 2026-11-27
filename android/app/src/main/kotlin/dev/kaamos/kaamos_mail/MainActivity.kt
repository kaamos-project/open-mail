package dev.kaamos.kaamos_mail

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * OAuth sign-in in a Custom Tab, the Android twin of `AuthSessionPlugin`
 * in `ios/Runner/AppDelegate.swift`.
 *
 * Dart calls `authenticate` with the provider's URL and the redirect's
 * scheme. The Custom Tab shows the page with the browser's own cookies and
 * saved passwords, which the app never sees. When the provider redirects to
 * the app's scheme, the intent-filter in `AndroidManifest.xml` brings this
 * activity back (`singleTask`, so the tab above it is closed) and
 * [onNewIntent] hands the URL to Dart.
 */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var pendingScheme: String? = null

    // Set once the tab covered the activity: the next resume without a
    // redirect means the user closed the tab.
    private var tabShown = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "authenticate") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val url = call.argument<String>("url")
                val scheme = call.argument<String>("callbackScheme")
                if (url == null || scheme == null) {
                    result.error("FAILED", "Missing url or callbackScheme.", null)
                    return@setMethodCallHandler
                }
                if (pending != null) {
                    result.error("BUSY", "A sign-in is already open.", null)
                    return@setMethodCallHandler
                }
                pending = result
                // Android lowercases intent schemes: compare in lowercase.
                pendingScheme = scheme.lowercase()
                tabShown = false
                try {
                    CustomTabsIntent.Builder().build().launchUrl(this, Uri.parse(url))
                } catch (e: ActivityNotFoundException) {
                    finish("FAILED", "No browser can open the sign-in page.")
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val data = intent.data ?: return
        val result = pending ?: return
        if (data.scheme?.lowercase() != pendingScheme) return
        clear()
        result.success(data.toString())
    }

    override fun onPause() {
        super.onPause()
        if (pending != null) tabShown = true
    }

    override fun onResume() {
        super.onResume()
        // onNewIntent runs before onResume, so a real redirect has already
        // cleared [pending] here.
        if (pending != null && tabShown) {
            finish("CANCELED", "Sign-in canceled.")
        }
    }

    private fun finish(code: String, message: String) {
        val result = pending ?: return
        clear()
        result.error(code, message, null)
    }

    private fun clear() {
        pending = null
        pendingScheme = null
        tabShown = false
    }

    private companion object {
        const val CHANNEL = "dev.kaamos.mail/oauth"
    }
}
