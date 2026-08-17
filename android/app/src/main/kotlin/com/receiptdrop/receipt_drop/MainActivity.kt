package com.receiptdrop.receipt_drop

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import com.receiptdrop.receipt_drop.paymentdetect.PaymentEventQueueStore
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
                    "openNotificationAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
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
}
