import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}
val mapsApiKey: String = localProperties.getProperty("MAPS_API_KEY") ?: ""

// Gradle can't read Dart's --dart-define values, so these are duplicated
// into local.properties for the native build — see PaymentNotificationClient.kt.
// SUPABASE_URL/SUPABASE_ANON_KEY here should match the same-named values the
// Flutter side uses (lib/core/config/env.dart); PAYMENT_NOTIFICATION_PROXY_SECRET
// is new and must match the Supabase Edge Function secret of the same name
// (see supabase/functions/.env.example) — this is the payment-notification
// pipeline's dev-only, personal-APK auth model, see docs/system/decisions.md.
val supabaseUrl: String = localProperties.getProperty("SUPABASE_URL") ?: ""
val supabaseAnonKey: String = localProperties.getProperty("SUPABASE_ANON_KEY") ?: ""
val paymentNotificationProxySecret: String =
    localProperties.getProperty("PAYMENT_NOTIFICATION_PROXY_SECRET") ?: ""

android {
    namespace = "com.receiptdrop.receipt_drop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    testOptions {
        // PaymentLogger calls android.util.Log; the default AGP unit-test
        // stub throws ("not mocked") rather than no-oping without this.
        unitTests.isReturnDefaultValues = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.receiptdrop.receipt_drop"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["mapsApiKey"] = mapsApiKey

        buildConfigField("String", "SUPABASE_URL", "\"$supabaseUrl\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"$supabaseAnonKey\"")
        buildConfigField(
            "String",
            "PAYMENT_NOTIFICATION_PROXY_SECRET",
            "\"$paymentNotificationProxySecret\"",
        )
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // NotificationManagerCompat.getEnabledListenerPackages — used by
    // MainActivity to check notification-listener access for the payment-
    // detection settings rows.
    implementation("androidx.core:core-ktx:1.13.1")
    testImplementation("junit:junit:4.13.2")
    // The android.jar stub used for local unit tests throws on org.json
    // calls ("not mocked") same as android.util.Log — this real
    // implementation shadows the stub on the test classpath, so
    // PaymentNotificationClient/CategoryMatcher's org.json usage works for
    // real in JVM unit tests without pulling in Robolectric.
    testImplementation("org.json:json:20231013")
}
