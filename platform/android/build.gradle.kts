plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
}

// 统一 Gradle/AGP 产物目录：build/android/gradle/<module>
allprojects {
    layout.buildDirectory.set(
        rootDir.resolve("../../build/android/gradle/${project.name}")
    )
}
