plugins {
    alias(libs.plugins.kotlinMultiplatform)
}

val isMac = System.getProperty("os.name").contains("Mac", ignoreCase = true)

kotlin {
    compilerOptions {
        apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_2_3)
        freeCompilerArgs.add("-opt-in=kotlinx.cinterop.ExperimentalForeignApi")
        freeCompilerArgs.add("-opt-in=kotlin.experimental.ExperimentalObjCName")
        freeCompilerArgs.add("-opt-in=com.sap.ec.InternalSdkApi")
    }
    jvmToolchain(17)

    if (isMac) {
        macosArm64().binaries.framework {
            baseName = "EngagementCloudSDKUnityKotlin"
            isStatic = false
            export(project(":engagement-cloud-sdk"))
            transitiveExport = false
            linkerOpts("-lsqlite3")
        }
    }

    sourceSets {
        val macosArm64Main by getting {
            dependencies {
                api(project(":engagement-cloud-sdk"))
                implementation(libs.koin.core)
                implementation(libs.kotlinx.coroutines.core)
            }
        }
    }
}
