plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.lenali"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "29.0.13113456"
    
    defaultConfig {
        targetSdk = 33
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    buildFeatures {
        buildConfig = true // Enable BuildConfig generation
    }

    defaultConfig {
        applicationId = "com.example.lenali"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        
        // Add these for background service
        buildConfigField("String", "NOTIFICATION_CHANNEL_ID", "\"lan_chat_background\"")
        buildConfigField("String", "NOTIFICATION_CHANNEL_NAME", "\"LAN Chat Background\"")
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isDebuggable = true
        }
    }

    lint {
        disable += listOf("InvalidPackage", "MissingPermission")
        checkDependencies = true
    }
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.work:work-runtime-ktx:2.8.1")
    implementation("androidx.lifecycle:lifecycle-process:2.6.2")
    
    // For background service
    implementation("androidx.lifecycle:lifecycle-service:2.6.2")
    
    // For notifications
    implementation("androidx.core:core:1.12.0")
    
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}