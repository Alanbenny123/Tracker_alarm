import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    FileInputStream(localPropertiesFile).use { localProperties.load(it) }
}
val googleMapsApiKey = localProperties.getProperty("GOOGLE_MAPS_API_KEY", "")
val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}
if (releaseRequested) {
    check(googleMapsApiKey.isNotBlank()) {
        "Release needs GOOGLE_MAPS_API_KEY in android/local.properties."
    }
    check(keystorePropertiesFile.isFile) {
        "Release needs android/key.properties. Copy android/key.properties.example and fill it in."
    }
    val requiredSigningProperties = listOf("storePassword", "keyPassword", "keyAlias", "storeFile")
    val missing = requiredSigningProperties.filter {
        keystoreProperties.getProperty(it).isNullOrBlank() ||
            keystoreProperties.getProperty(it).startsWith("REPLACE_WITH")
    }
    check(missing.isEmpty()) { "Release signing is incomplete in android/key.properties: ${missing.joinToString()}" }
    check(file(keystoreProperties.getProperty("storeFile")).isFile) {
        "Release keystore file in android/key.properties does not exist."
    }
}

android {
    namespace = "com.trackeralarm.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    buildFeatures { resValues = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "com.trackeralarm.app"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue("string", "google_maps_api_key", googleMapsApiKey)
    }
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }
    buildTypes { release { signingConfig = signingConfigs.getByName("release") } }
    testOptions { unitTests.isIncludeAndroidResources = true }
}

kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }

flutter { source = "../.." }
// Flutter's asset-copy task is not wired into AGP 9 host-test packaging.
tasks.matching { it.name == "packageDebugUnitTestForUnitTest" }.configureEach {
    dependsOn("copyFlutterAssetsDebug")
}
dependencies {
    implementation("com.google.android.gms:play-services-location:21.3.0")
    implementation("com.google.android.gms:play-services-maps:20.0.0")
    implementation("com.google.android.libraries.places:places:6.0.2")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.17")
}
