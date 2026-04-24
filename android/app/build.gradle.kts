plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.jmk.leggio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.jmk.leggio"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

}

flutter {
    source = "../.."
}

tasks.register("renameApk") {
    doLast {
        val versionName = android.defaultConfig.versionName ?: "unknown"
        val apkDir = file("${project.buildDir}/outputs/flutter-apk")
        val originalApk = File(apkDir, "app-release.apk")
        if (originalApk.exists()) {
            val namedApk = File(apkDir, "leggio-${versionName}.apk")
            originalApk.copyTo(namedApk, overwrite = true)
            println("APK copied to: leggio-${versionName}.apk")
        }
    }
}

tasks.register("deployApk") {
    doLast {
        val remoteUser = "chuck"
        val remoteHost = "teutonia.kreilos.fr"
        val remoteDir = "/var/www/android"
        val versionName = android.defaultConfig.versionName ?: "unknown"
        val apkName = "leggio-${versionName}.apk"
        val apkPath = "${project.rootDir}/../build/app/outputs/flutter-apk/${apkName}"
        exec {
            commandLine("scp", apkPath, "${remoteUser}@${remoteHost}:${remoteDir}/${apkName}")
        }
        exec {
            commandLine("ssh", "${remoteUser}@${remoteHost}",
                """cd ${remoteDir} && ls -t *.apk | awk 'BEGIN {
                    print "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Leggio APK</title>"
                    print "<style>body{font-family:sans-serif;max-width:600px;margin:40px auto;padding:0 20px}"
                    print "a{display:block;padding:8px 0;color:#1a73e8;text-decoration:none}"
                    print "a:hover{text-decoration:underline}</style></head><body>"
                    print "<h1>Leggio</h1>"
                }
                { print "<a href=\"" $0 "\">" $0 "</a>" }
                END { print "</body></html>" }' > index.html""")
        }
        println("Deployed: https://android.kreilos.fr/${apkName}")
    }
}

tasks.whenTaskAdded {
    if (name == "assembleRelease") {
        finalizedBy("renameApk")
    }
}

tasks.named("renameApk") {
    finalizedBy("deployApk")
}
