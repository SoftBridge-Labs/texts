plugins {
    id("com.android.library")
}

android {
    namespace = "io.adaptant.labs.flutter_windowmanager"
    compileSdk = 36

    defaultConfig {
        minSdk = 16
        targetSdk = 36
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("androidx.annotation:annotation:1.6.0")
}
