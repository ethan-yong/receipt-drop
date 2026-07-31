package com.receiptdrop.receipt_drop

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
    }
}
