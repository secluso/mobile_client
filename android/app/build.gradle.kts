plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import groovy.json.JsonSlurper
import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import java.io.FileInputStream
import org.gradle.api.Project
import org.gradle.api.tasks.compile.JavaCompile
import org.gradle.jvm.tasks.Jar
import java.util.Base64
import java.util.Properties

fun androidDevDependencyPluginNames(flutterProjectDir: File): Set<String> {
    val pluginsFile = flutterProjectDir.resolve(".flutter-plugins-dependencies")
    if (!pluginsFile.exists()) {
        return emptySet()
    }

    val parsed = JsonSlurper().parseText(pluginsFile.readText()) as? Map<*, *> ?: return emptySet()
    val plugins = (parsed["plugins"] as? Map<*, *>) ?: return emptySet()
    val androidPlugins = plugins["android"] as? List<*> ?: return emptySet()

    return androidPlugins.mapNotNull { plugin ->
        val pluginMap = plugin as? Map<*, *> ?: return@mapNotNull null
        val isDevDependency = pluginMap["dev_dependency"] as? Boolean ?: false
        if (isDevDependency) pluginMap["name"] as? String else null
    }.toSet()
}

fun stripPluginRegistrations(content: String, pluginNames: Set<String>): String {
    var updatedContent = content
    for (pluginName in pluginNames) {
        val pattern = Regex(
            """(?m)^\s*try \{\R\s*flutterEngine\.getPlugins\(\)\.add\(new [^\r\n]+\);\R\s*\} catch \(Exception e\) \{\R\s*Log\.e\(TAG, "Error registering plugin ${Regex.escape(pluginName)}, [^"]+", e\);\R\s*\}\R?"""
        )
        updatedContent = updatedContent.replace(pattern, "")
    }
    return updatedContent
}

fun decodeDartDefines(rawValue: String?): Map<String, String> {
    if (rawValue.isNullOrBlank()) {
        return emptyMap()
    }
    return rawValue
        .split(',')
        .mapNotNull { encoded ->
            if (encoded.isBlank()) {
                return@mapNotNull null
            }
            val normalized = encoded.padEnd((encoded.length + 3) / 4 * 4, '=')
            val decoded = String(Base64.getUrlDecoder().decode(normalized))
            val separator = decoded.indexOf('=')
            if (separator <= 0) {
                return@mapNotNull null
            }
            decoded.substring(0, separator) to decoded.substring(separator + 1)
        }
        .toMap()
}

fun Project.addCameraAndroidCameraxWorkaround() {
    rootProject.subprojects
        .firstOrNull { it.name == "camera_android_camerax" }
        ?.dependencies
        ?.add("implementation", "androidx.concurrent:concurrent-futures:1.1.0")
}

val fdroidBuildEnabled =
    providers.environmentVariable("SECLUSO_FDROID_BUILD").orNull == "1" ||
        decodeDartDefines(
            providers.gradleProperty("dart-defines").orNull ?: System.getProperty("dart-defines")
        )["SECLUSO_FDROID_BUILD"] == "true"
val fdroidExcludedPluginNames =
    setOf("firebase_core", "firebase_messaging", "objectbox_flutter_libs")
val fdroidGeneratedRegistrantDir =
    layout.buildDirectory.dir("generated/source/secluso/fdroid")
val generateFdroidGeneratedPluginRegistrant =
    tasks.register("generateFdroidGeneratedPluginRegistrant") {
        val sourceFile =
            projectDir.resolve("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
        val outputDir = fdroidGeneratedRegistrantDir.get().asFile
        val outputFile = outputDir.resolve("io/flutter/plugins/GeneratedPluginRegistrant.java")
        inputs.file(sourceFile)
        outputs.file(outputFile)
        doLast {
            if (!sourceFile.exists()) {
                throw org.gradle.api.GradleException(
                    "GeneratedPluginRegistrant source missing: ${sourceFile.absolutePath}"
                )
            }
            val strippedPluginNames =
                androidDevDependencyPluginNames(rootProject.projectDir.parentFile) +
                    if (fdroidBuildEnabled) fdroidExcludedPluginNames else emptySet()
            val strippedContent =
                stripPluginRegistrations(sourceFile.readText(), strippedPluginNames)
            outputFile.parentFile.mkdirs()
            outputFile.writeText(strippedContent)
            logger.lifecycle(
                "Generated F-Droid GeneratedPluginRegistrant without: ${strippedPluginNames.joinToString(", ")}"
            )
        }
    }

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val requiredKeystoreKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val allowUnsignedRelease =
    providers.environmentVariable("SECLUSO_ALLOW_UNSIGNED_RELEASE").orNull == "1"
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val missingKeystoreKeys = requiredKeystoreKeys.filter { key ->
    keystoreProperties.getProperty(key).isNullOrBlank()
}
val configuredStoreFile =
    keystoreProperties.getProperty("storeFile")?.trim()?.takeIf { it.isNotEmpty() }?.let { path ->
        val candidate = File(path)
        if (candidate.isAbsolute) candidate else keystorePropertiesFile.parentFile.resolve(path)
    }
val hasConfiguredKeystore = keystorePropertiesFile.exists() && missingKeystoreKeys.isEmpty()
val hasValidKeystore = hasConfiguredKeystore && configuredStoreFile?.isFile == true
if (!allowUnsignedRelease && !hasValidKeystore) {
    val missingParts = if (keystorePropertiesFile.exists()) {
        if (missingKeystoreKeys.isNotEmpty()) {
            "missing keys: ${missingKeystoreKeys.joinToString(", ")}"
        } else {
            "keystore file not found: ${configuredStoreFile?.absolutePath ?: "<unresolved>"}"
        }
    } else {
        "missing key.properties"
    }
    logger.warn("Android release signing disabled ($missingParts). Debug builds will still work.")
} else if (allowUnsignedRelease && keystorePropertiesFile.exists()) {
    logger.lifecycle(
        "SECLUSO_ALLOW_UNSIGNED_RELEASE=1; ignoring android/key.properties during unsigned release build."
    )
}

gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any { it.name.contains("Release", ignoreCase = true) }
    if (wantsRelease && !hasValidKeystore && !allowUnsignedRelease) {
        val missingParts = if (keystorePropertiesFile.exists()) {
            if (missingKeystoreKeys.isNotEmpty()) {
                "missing keys: ${missingKeystoreKeys.joinToString(", ")}"
            } else {
                "keystore file not found: ${configuredStoreFile?.absolutePath ?: "<unresolved>"}"
            }
        } else {
            "missing key.properties"
        }
        throw org.gradle.api.GradleException(
            "Release build requires signing config ($missingParts). " +
                "Create key.properties with storeFile, storePassword, keyAlias, keyPassword, " +
                "or set SECLUSO_ALLOW_UNSIGNED_RELEASE=1 for a verification-only unsigned build."
        )
    }
}

android {
    namespace = "com.secluso.mobile"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.secluso.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Device Farm runs the screenshot pass through Android instrumentation, so we need a real instrumentation
        // runner here instead of relying on Flutter's normal app entry only
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    sourceSets {
        getByName("main") {
            java.srcDir(fdroidGeneratedRegistrantDir)
        }
        getByName("androidTest") {
            assets.srcDir(project.file("../../tool"))
        }
    }

    packaging {
        jniLibs {
            // Direct APK installs from Flutter/ADB are not emitted with 16 KB page
            // alignment today, so keep native libraries compressed to avoid the
            // device-side compatibility warning while retaining 16 KB-compatible
            // ELF alignment inside the libraries themselves.
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        if (!allowUnsignedRelease && hasValidKeystore) {
            create("release") {
                storeFile = configuredStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (!allowUnsignedRelease && hasValidKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        } 
    }
}

  val abiCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)
  android.applicationVariants.configureEach {
      val variant = this
      variant.outputs.forEach { output ->
          val abiVersionCode = abiCodes[output.filters.find { it.filterType == "ABI" }?.identifier]
          if (abiVersionCode != null) {
              (output as ApkVariantOutputImpl).versionCodeOverride = variant.versionCode * 10 + abiVersionCode
          }
      }
  }

flutter {
    source = "../.."
}

gradle.projectsEvaluated {
    addCameraAndroidCameraxWorkaround()
}

val mainRegistrantFile =
    projectDir.resolve("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java").absoluteFile
tasks.matching { it.name.startsWith("compile") && it.name.endsWith("JavaWithJavac") }.configureEach {
    dependsOn(generateFdroidGeneratedPluginRegistrant)
    if (this is JavaCompile) {
        exclude { fileTreeElement ->
            fileTreeElement.file.absoluteFile == mainRegistrantFile
        }
    }
}

tasks.matching { it.name.startsWith("compile") && it.name.endsWith("Kotlin") }.configureEach {
    dependsOn(generateFdroidGeneratedPluginRegistrant)
}

tasks.withType<Jar>().configureEach {
    if (name.startsWith("packJniLibsflutterBuild")) {
        isPreserveFileTimestamps = false
        isReproducibleFileOrder = true
    }
}

val firebaseDependencyGroup = listOf("com", "google", "firebase").joinToString(".")
val firebaseMessagingArtifact = listOf("firebase", "messaging").joinToString("-")

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    if (!fdroidBuildEnabled) {
        implementation("$firebaseDependencyGroup:$firebaseMessagingArtifact:24.1.1")
    }
    implementation("androidx.media3:media3-exoplayer:1.7.1")
    implementation("androidx.media3:media3-ui:1.7.1")
    // Keep these AndroidX test libs on versions that work nicely with the rest
    // of the Flutter / Gradle stack already in this app. 
    //
    // In practice, we only need these:
    // - runner: actually launches the instrumentation process on Device Farm
    // - ext:junit: normal JUnit4 
    // - core: small Android test utilities
    // - uiautomator: gives us device-level screenshots and app launching
    androidTestImplementation("androidx.test:runner:1.2.0")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test:core:1.5.0")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
}


// The camera hub's TLS stack verifies certificates through the Android system verifier
repositories {
    maven {
        url = uri("/Users/john-study/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/rustls-platform-verifier-android-0.1.1/maven")
    }
}

dependencies {
    implementation("rustls:rustls-platform-verifier:0.1.1")
}
