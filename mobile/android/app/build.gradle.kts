plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// A release key is supplied externally. Never fall back to the debug keystore.
val releaseStorePath = providers.environmentVariable("ABIGAIL_ANDROID_KEYSTORE_PATH").orNull
val releaseStorePassword = providers.environmentVariable("ABIGAIL_ANDROID_KEYSTORE_PASSWORD").orNull
val releaseKeyAlias = providers.environmentVariable("ABIGAIL_ANDROID_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("ABIGAIL_ANDROID_KEY_PASSWORD").orNull

android {
    namespace = "com.abigailovos.abigailovos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.abigailovos.abigailovos"
        manifestPlaceholders["appLabel"] = "AbigailOvos"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (!releaseStorePath.isNullOrBlank()) storeFile = file(releaseStorePath)
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        debug {
            if (providers.gradleProperty("isolatedTest").orNull == "true") {
                applicationIdSuffix = ".teste"
            }
        }
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Run only for release tasks, so debug/test builds do not need production keys.
tasks.configureEach {
    if (name == "preReleaseBuild") {
        doFirst {
            check(!releaseStorePath.isNullOrBlank() && !releaseStorePassword.isNullOrBlank()
                    && !releaseKeyAlias.isNullOrBlank() && !releaseKeyPassword.isNullOrBlank()) {
                "Release exige uma chave própria e as variáveis ABIGAIL_ANDROID_KEYSTORE_PATH, " +
                    "ABIGAIL_ANDROID_KEYSTORE_PASSWORD, ABIGAIL_ANDROID_KEY_ALIAS e ABIGAIL_ANDROID_KEY_PASSWORD."
            }
            val releaseStore = file(releaseStorePath!!)
            check(releaseStore.isFile && !releaseStore.name.equals("debug.keystore", ignoreCase = true)
                    && !releaseKeyAlias.equals("androiddebugkey", ignoreCase = true)) {
                "O keystore de release não existe ou corresponde à configuração de depuração."
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
