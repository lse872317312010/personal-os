plugins { id("com.android.application") }

android {
    namespace = "com.personalos.wechatcollector"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.personalos.wechatcollector"
        minSdk = 26
        targetSdk = 35
        versionCode = 4
        versionName = "0.2.2"
    }

    buildTypes {
        release { isMinifyEnabled = false }
    }
}

dependencies {
    implementation("androidx.core:core:1.15.0")
}
