package com.receiptdrop.receipt_drop

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import androidx.core.app.NotificationManagerCompat
import com.receiptdrop.receipt_drop.paymentdetect.PaymentEventQueueStore
import com.receiptdrop.receipt_drop.paymentdetect.PaymentListenerHeartbeat
import com.receiptdrop.receipt_drop.paymentdetect.PaymentNotificationListenerService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Exposes Activity.getReferrer() so the Dart side can attempt best-effort
    // identification of the app that shared a receipt into us, before OCR.
    // The receive_sharing_intent plugin doesn't expose this itself — see
    // lib/features/share/share_referrer_reader_io.dart and
    // docs/plans/2026-07-30-post-share-receipt-notification.md.
    private val shareReferrerChannel = "com.receiptdrop.receipt_drop/share_referrer"

    // Bridges the native payment-notification-detection feature (see
    // android/app/src/main/kotlin/.../paymentdetect/) to Flutter — permission
    // check/open helpers, plus draining the durable native event queue into
    // lib/core/payment_detection/payment_event_drain_service.dart.
    private val paymentEventsChannel = "com.receiptdrop.receipt_drop/payment_events"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        rebindNotificationListenerIfNeeded()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareReferrerChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getReferrerPackage") {
                    // getReferrer() returns an android-app://<package> Uri set by
                    // whichever app started this Activity (independent of
                    // startActivityForResult, unlike getCallingPackage()), or null
                    // when nothing set one (e.g. launched from the home screen).
                    val pkg = referrer?.takeIf { it.scheme == "android-app" }?.host
                    result.success(pkg)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, paymentEventsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isNotificationAccessGranted" -> result.success(isNotificationAccessGranted())
                    "getNotificationListenerStatus" -> result.success(notificationListenerStatus())
                    "openNotificationAccessSettings" -> {
                        startActivity(notificationAccessSettingsIntent())
                        result.success(null)
                    }
                    "openAutostartSettings" -> {
                        startActivity(autostartSettingsIntent())
                        result.success(null)
                    }
                    "isOverlayPermissionGranted" -> result.success(Settings.canDrawOverlays(this))
                    "openOverlayPermissionSettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                        result.success(null)
                    }
                    "drainPaymentEvents" -> {
                        val events = PaymentEventQueueStore(applicationContext).drainAll()
                        result.success(events.map { it.toMap() })
                    }
                    "acknowledgePaymentEvents" -> {
                        val ids = (call.arguments as? List<*>)
                            ?.filterIsInstance<String>()
                            ?.toSet()
                            ?: emptySet()
                        PaymentEventQueueStore(applicationContext).acknowledge(ids)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isNotificationAccessGranted(): Boolean {
        return NotificationManagerCompat.getEnabledListenerPackages(this).contains(packageName)
    }

    /// Reports whether notification detection is permitted *and* actually
    /// running — see PaymentListenerHeartbeat for why those differ. Asks for
    /// a rebind on the way out when it's permitted but dead, so simply
    /// opening this screen is itself a recovery attempt.
    private fun notificationListenerStatus(): Map<String, Any?> {
        val enabled = isNotificationAccessGranted()
        val heartbeat = PaymentListenerHeartbeat(applicationContext)
        val connected = enabled && heartbeat.isConnected()
        if (enabled && !connected) rebindNotificationListenerIfNeeded()
        return mapOf(
            "enabled" to enabled,
            "connected" to connected,
            "neverConnected" to heartbeat.hasNeverConnected(),
            "lastConnectedAtEpochMs" to heartbeat.lastConnectedAt(),
            "lastNotificationAtEpochMs" to heartbeat.lastNotificationAt(),
        )
    }

    /// Best-effort deep link to the OEM's "background autostart" allowlist,
    /// which is a vendor screen with no AOSP equivalent — Android has no
    /// standard intent for it, so each skin needs its own component. Falls
    /// back to this app's system settings page when nothing resolves.
    private fun autostartSettingsIntent(): Intent {
        val candidates = listOf(
            // Xiaomi MIUI / HyperOS
            "com.miui.securitycenter" to
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            // Oppo ColorOS / Realme
            "com.coloros.safecenter" to
                "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to
                "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
            // Vivo Funtouch / OriginOS
            "com.vivo.permissionmanager" to
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            // Huawei EMUI
            "com.huawei.systemmanager" to
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to
                "com.huawei.systemmanager.optimize.process.ProtectActivity",
        )
        for ((pkg, cls) in candidates) {
            val intent = Intent().setComponent(ComponentName(pkg, cls))
            if (intent.resolveActivity(packageManager) != null) return intent
        }
        return Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName"),
        )
    }

    /// Asks the system to re-bind PaymentNotificationListenerService.
    ///
    /// Having notification access *granted* is not the same as the listener
    /// being *bound*: after an app update, a force-stop, or an aggressive
    /// OEM memory manager (MIUI/HyperOS especially) kills the process, the
    /// permission stays on in Settings while the service is never rebound —
    /// so payments are silently never detected and the toggle still reads
    /// "allowed", which makes it look like the feature is simply broken.
    /// requestRebind is the documented recovery for exactly that state and
    /// is a no-op when the listener is already connected.
    private fun rebindNotificationListenerIfNeeded() {
        if (!isNotificationAccessGranted()) return
        runCatching {
            NotificationListenerService.requestRebind(
                ComponentName(this, PaymentNotificationListenerService::class.java),
            )
        }
    }

    /// Opens this app's notification-listener toggle when the OS supports
    /// it (API 30+), falling back to the all-apps list on older devices or
    /// OEMs that reject the detail intent.
    private fun notificationAccessSettingsIntent(): Intent {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val detail = Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
            val component = ComponentName(
                this,
                PaymentNotificationListenerService::class.java,
            )
            detail.putExtra(
                Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                component.flattenToString(),
            )
            if (detail.resolveActivity(packageManager) != null) return detail
        }
        return Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
    }
}
