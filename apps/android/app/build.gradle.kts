plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.castsprint.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.castsprint.android"
        minSdk = 29 // Android 10: required for AudioPlaybackCapture
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
        allWarningsAsErrors = true
    }
    lint {
        abortOnError = true
        warningsAsErrors = false
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
