plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    id("io.github.gradle-nexus.publish-plugin") version "2.0.0"
}

group = "io.github.flutterplayer"
version = providers.gradleProperty("VERSION_NAME").getOrElse("1.0.4")

nexusPublishing {
    packageGroup.set("io.github.flutterplayer")
    repositories {
        sonatype {
            nexusUrl.set(uri("https://ossrh-staging-api.central.sonatype.com/service/local/"))
            snapshotRepositoryUrl.set(uri("https://central.sonatype.com/repository/maven-snapshots/"))
            username.set(providers.environmentVariable("NEXUS_USERNAME"))
            password.set(providers.environmentVariable("NEXUS_PASSWORD"))
        }
    }
}

// 统一 Gradle/AGP 产物目录：build/android/gradle/<module>
allprojects {
    layout.buildDirectory.set(
        rootDir.resolve("../../build/android/gradle/${project.name}")
    )
}
