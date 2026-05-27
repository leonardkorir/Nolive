import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    FileInputStream(localPropertiesFile).use(localProperties::load)
}
val releaseStoreFilePath = keystoreProperties.getProperty("storeFile")?.trim()
val releaseKeyAlias = keystoreProperties.getProperty("keyAlias")?.trim()
val releaseStorePassword = keystoreProperties.getProperty("storePassword")?.trim()
val releaseKeyPassword = keystoreProperties.getProperty("keyPassword")?.trim()
val releaseSigningReady =
    !releaseStoreFilePath.isNullOrBlank() &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank() &&
        !releaseStoreFilePath.contains("debug.keystore") &&
        releaseKeyAlias != "androiddebugkey"
if (gradle.startParameter.taskNames.any { it.contains("Release") } &&
    !releaseSigningReady) {
    throw GradleException(
        "Android release signing is not configured. Run scripts/create_main_app_android_signing.sh or provide a complete android/key.properties.",
    )
}
tasks.configureEach {
    if (name.contains("Release")) {
        doFirst {
            if (!releaseSigningReady) {
                throw GradleException(
                    "Android release signing is not configured. Run scripts/create_main_app_android_signing.sh or provide a complete android/key.properties.",
                )
            }
        }
    }
}
val androidSdkDir =
    localProperties.getProperty("sdk.dir")?.trim()
        ?: System.getenv("ANDROID_SDK_ROOT")?.trim()
        ?: System.getenv("ANDROID_HOME")?.trim()
val rustDanmakuMaskEnabled =
    (
        localProperties.getProperty("nolive.buildRustDanmakuMask")?.trim()
            ?: System.getenv("NOLIVE_BUILD_RUST_DANMAKU_MASK")?.trim()
            ?: "false"
        ).equals("true", ignoreCase = true)
val rustJniLibsDir = layout.buildDirectory.dir("generated/rustJniLibs")
val rustBuildScript = rootProject.file("../rust/build_android_danmaku_mask.sh")

val buildRustDanmakuMask by tasks.registering(Exec::class) {
    inputs.dir(rootProject.file("../rust/danmaku_mask"))
    inputs.file(rustBuildScript)
    inputs.property("rustDanmakuMaskEnabled", rustDanmakuMaskEnabled)
    outputs.dir(rustJniLibsDir)

    doFirst {
        delete(rustJniLibsDir)
        rustJniLibsDir.get().asFile.mkdirs()
    }

    commandLine(
        "bash",
        rustBuildScript.absolutePath,
        rustJniLibsDir.get().asFile.absolutePath,
        androidSdkDir ?: "",
        rustDanmakuMaskEnabled.toString(),
    )

    doLast {
        if (!rustDanmakuMaskEnabled) {
            logger.lifecycle(
                "Rust danmaku mask build disabled; Android runtime will use Dart fallback.",
            )
        } else {
            logger.lifecycle("Rust danmaku mask native artifacts built.")
        }
    }
}

android {
    namespace = "app.nolive.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // media_kit_libs_android_video requires extracted native libraries.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    sourceSets {
        getByName("main").jniLibs.srcDir(rustJniLibsDir)
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            if (releaseSigningReady) {
                storeFile = file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    defaultConfig {
        applicationId = "app.nolive.mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            if (releaseSigningReady) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

val generatedPluginRegistrantFile =
    project.file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
val sanitizeGeneratedPluginRegistrantForRelease by tasks.registering {
    doLast {
        if (!generatedPluginRegistrantFile.exists()) {
            return@doLast
        }
        val original = generatedPluginRegistrantFile.readText()
        val sanitized =
            original.replace(
                Regex(
                    """\s*try \{\s*flutterEngine\.getPlugins\(\)\.add\(new dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)\);\s*\} catch \(Exception e\) \{\s*Log\.e\(TAG, "Error registering plugin integration_test, dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin", e\);\s*\}\s*""",
                    setOf(RegexOption.DOT_MATCHES_ALL),
                ),
                "\n",
            )
        if (sanitized != original) {
            generatedPluginRegistrantFile.writeText(sanitized)
            logger.lifecycle(
                "Sanitized stale integration_test registrant entry for release build.",
            )
        }
    }
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(sanitizeGeneratedPluginRegistrantForRelease)
}

flutter {
    source = "../.."
}

tasks.named("preBuild") {
    dependsOn(buildRustDanmakuMask)
}
