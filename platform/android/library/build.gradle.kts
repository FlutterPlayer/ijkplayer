plugins {
    alias(libs.plugins.android.library)
    `maven-publish`
    signing
}

android {
    namespace = "tv.danmaku.ijk.media.player"
    compileSdk = libs.versions.compileSdk.get().toInt()
    ndkVersion = libs.versions.ndk.get()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()

        consumerProguardFiles("proguard-rules.pro")

        // 整条原生栈（ijkplayer / ijksdl / ijksoundtouch / ijkj4a）由 CMake 构建
        externalNativeBuild {
            cmake {
                val stl = providers.gradleProperty("IJK_CXX_STL").getOrElse("c++_static")
                arguments += listOf("-DANDROID_STL=$stl", "-DANDROID_TOOLCHAIN=clang")
                targets += "ijkplayer"
            }
        }

        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = libs.versions.cmake.get()
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        abortOnError = false
    }

    // 保持对外 AAR 文件名不变：fplayercore-release.aar
    base {
        archivesName.set("fplayercore")
    }

    // AGP 8：声明可发布的变体，供 maven-publish 使用
    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar"))))
}

afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])
                groupId = providers.gradleProperty("GROUP").get()
                artifactId = providers.gradleProperty("POM_ARTIFACT_ID").get()
                version = providers.gradleProperty("VERSION_NAME").get()
                pom {
                    name.set(providers.gradleProperty("POM_NAME").getOrElse("fplayercore"))
                    description.set("Video player based on FFmpeg 8 (ijkplayer)")
                    url.set("https://github.com/FlutterPlayer/ijkplayer")
                    licenses {
                        license {
                            name.set("LGPL-2.1")
                            url.set("https://www.gnu.org/licenses/lgpl-2.1.html")
                        }
                    }
                    developers {
                        developer {
                            id.set("bileskou")
                            name.set("bileskou")
                        }
                    }
                    scm {
                        url.set("https://github.com/FlutterPlayer/ijkplayer.git")
                    }
                }
            }
        }
    }
    signing {
        val key = providers.gradleProperty("signingKey").orNull
        if (!key.isNullOrBlank()) {
            useInMemoryPgpKeys(
                providers.gradleProperty("signingKeyId").orNull,
                key,
                providers.gradleProperty("signingPassword").orNull
            )
            sign(publishing.publications["release"])
        }
    }
}
