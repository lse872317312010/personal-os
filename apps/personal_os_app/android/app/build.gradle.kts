plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val personalOsOpenAiEnabled =
    providers.gradleProperty("personalOsOpenAiEnabled").orNull == "true"
val personalOsOpenAiModel =
    providers.gradleProperty("personalOsOpenAiModel").orNull?.trim().orEmpty()

require(!personalOsOpenAiEnabled || personalOsOpenAiModel.isNotEmpty()) {
    "personalOsOpenAiModel is required when personalOsOpenAiEnabled=true"
}
require(
    personalOsOpenAiModel.isEmpty() ||
        personalOsOpenAiModel.matches(Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")),
) {
    "personalOsOpenAiModel contains unsupported characters"
}

android {
    namespace = "com.personalos.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }

    defaultConfig {
        applicationId = "com.personalos.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField(
            "boolean",
            "PERSONAL_OS_OPENAI_ENABLED",
            personalOsOpenAiEnabled.toString(),
        )
        buildConfigField(
            "String",
            "PERSONAL_OS_OPENAI_MODEL",
            "\"$personalOsOpenAiModel\"",
        )
    }

    buildFeatures {
        buildConfig = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("net.zetetic:sqlcipher-android:4.17.0@aar")
    implementation("androidx.sqlite:sqlite:2.7.0")
}
