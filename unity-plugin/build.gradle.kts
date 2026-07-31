// Build orchestration for the Unity plugin (Section F of the phase-2 plan).
//
// Wires together:
//   1. `:engagement-cloud-sdk:linkReleaseFrameworkMacosArm64` (upstream)
//   2. `:unity-plugin:kotlin:linkReleaseFrameworkMacosArm64` (upstream)
//   3. `xcodebuild` on the shim Xcode project (external)
//   4. copying the three artifacts into `com.sap.ec.unity/Plugins/macOS/`
//   5. packaging the UPM package into a `.tgz`
//   6. exporting a `.unitypackage` via the Unity CLI (skipped if UNITY_PATH
//      is unset)

import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.Property
import org.gradle.api.provider.ProviderFactory
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.OutputFile
import org.gradle.api.tasks.TaskAction
import org.gradle.process.ExecOperations
import javax.inject.Inject

plugins {
    base
}

// Convenience refs -----------------------------------------------------------

val engagementSdkFrameworkTask = ":engagement-cloud-sdk:linkReleaseFrameworkMacosArm64"
val unityKotlinFrameworkTask = ":unity-plugin:kotlin:linkReleaseFrameworkMacosArm64"

val engagementSdkFrameworkDir = layout.projectDirectory
    .dir("../engagement-cloud-sdk/build/bin/macosArm64/releaseFramework/EngagementCloudSDK.framework")

val unityKotlinFrameworkDir = layout.projectDirectory
    .dir("kotlin/build/bin/macosArm64/releaseFramework/EngagementCloudSDKUnityKotlin.framework")

val shimDir = layout.projectDirectory.dir("shim")
val shimBundleDir = shimDir.dir(".build/products/Release/EngagementCloudSDKUnity.bundle")

val upmRoot = layout.projectDirectory.dir("com.sap.ec.unity")
val pluginsMacosDir = upmRoot.dir("Plugins/macOS")

val shimFrameworksStage = shimDir.dir(".build/frameworks")

val upmVersionProvider = providers.provider {
    val pkg = upmRoot.file("package.json").asFile.readText()
    Regex("""\"version\"\s*:\s*\"([^\"]+)\"""")
        .find(pkg)?.groupValues?.get(1)
        ?: error("Failed to read version from package.json")
}

// -----------------------------------------------------------------------------
// Task types — abstract classes with @Inject ExecOperations. This is the
// Gradle 8+ replacement for the old top-level `exec { }` DSL.
// -----------------------------------------------------------------------------

abstract class StageShimFrameworksTask : DefaultTask() {
    @get:Inject abstract val execOperations: ExecOperations

    @get:InputDirectory abstract val mainFramework: DirectoryProperty
    @get:InputDirectory abstract val unityKotlinFramework: DirectoryProperty
    @get:OutputDirectory abstract val stageDir: DirectoryProperty

    @TaskAction
    fun run() {
        val stage = stageDir.get().asFile
        stage.deleteRecursively()
        stage.mkdirs()
        execOperations.exec {
            workingDir = stage
            commandLine("ln", "-s", mainFramework.get().asFile.absolutePath, "EngagementCloudSDK.framework")
        }
        execOperations.exec {
            workingDir = stage
            commandLine("ln", "-s", unityKotlinFramework.get().asFile.absolutePath, "EngagementCloudSDKUnityKotlin.framework")
        }
    }
}

abstract class AssembleShimTask : DefaultTask() {
    @get:Inject abstract val execOperations: ExecOperations

    @get:InputDirectory abstract val shimSrcDir: DirectoryProperty
    @get:InputFile abstract val projectYml: RegularFileProperty
    @get:InputDirectory abstract val frameworksStage: DirectoryProperty
    @get:Input abstract val wrapperVersion: Property<String>
    @get:OutputDirectory abstract val bundleDir: DirectoryProperty

    @TaskAction
    fun run() {
        val shim = projectYml.get().asFile.parentFile

        execOperations.exec {
            commandLine("bash", "-c",
                "command -v xcodegen >/dev/null 2>&1 || { echo 'xcodegen not found - run: brew install xcodegen' >&2; exit 1; }")
        }
        execOperations.exec {
            workingDir = shim
            commandLine("xcodegen", "generate")
        }
        execOperations.exec {
            workingDir = shim
            commandLine(
                "xcodebuild",
                "-project", "EngagementCloudSDKUnity.xcodeproj",
                "-scheme", "EngagementCloudSDKUnity",
                "-configuration", "Release",
                "-sdk", "macosx",
                "-destination", "generic/platform=macOS",
                "ARCHS=arm64",
                "ONLY_ACTIVE_ARCH=NO",
                "EC_FRAMEWORKS_DIR=${frameworksStage.get().asFile.absolutePath}",
                "EC_WRAPPER_VERSION_STR=${wrapperVersion.get()}",
                "BUILD_DIR=${shim.absolutePath}/.build/products",
                "build"
            )
        }

        val bundleBinary = bundleDir.get().file("Contents/MacOS/EngagementCloudSDKUnity").asFile
        check(bundleBinary.exists()) {
            "xcodebuild reported success but produced no binary at ${bundleBinary.absolutePath}"
        }
    }
}

abstract class PackUpmTask : DefaultTask() {
    @get:Inject abstract val execOperations: ExecOperations

    @get:InputDirectory abstract val upmPackageDir: DirectoryProperty
    @get:OutputFile abstract val outputTarball: RegularFileProperty

    @TaskAction
    fun run() {
        val tarball = outputTarball.get().asFile
        tarball.parentFile.mkdirs()
        execOperations.exec {
            workingDir = upmPackageDir.get().asFile
            commandLine(
                "tar", "czf", tarball.absolutePath,
                "--exclude=.gitignore",
                "--exclude=Plugins/macOS/.gitkeep",
                "."
            )
        }
        logger.lifecycle("Packed UPM: ${tarball.absolutePath}")
    }
}

abstract class ExportUnityPackageTask : DefaultTask() {
    @get:Inject abstract val execOperations: ExecOperations
    @get:Inject abstract val providerFactory: ProviderFactory

    @get:InputDirectory abstract val upmPackageDir: DirectoryProperty
    @get:Input abstract val version: Property<String>
    @get:OutputDirectory abstract val distDir: DirectoryProperty

    @TaskAction
    fun run() {
        val unityPath = providerFactory.environmentVariable("UNITY_PATH").orNull
        if (unityPath.isNullOrBlank()) {
            logger.warn("[unity-plugin] UNITY_PATH not set - skipping .unitypackage export. Set it to the Unity executable path to enable.")
            return
        }

        val dist = distDir.get().asFile
        dist.mkdirs()
        val outputFile = File(dist, "EngagementCloud-${version.get()}.unitypackage")

        val scratchProject = temporaryDir
        val assets = File(scratchProject, "Assets")
        val packages = File(scratchProject, "Packages")
        assets.mkdirs()
        packages.mkdirs()
        val symlink = File(assets, "com.sap.ec.unity")
        if (symlink.exists()) symlink.delete()
        execOperations.exec {
            commandLine("ln", "-s", upmPackageDir.get().asFile.absolutePath, symlink.absolutePath)
        }

        execOperations.exec {
            commandLine(
                unityPath,
                "-batchmode",
                "-nographics",
                "-quit",
                "-projectPath", scratchProject.absolutePath,
                "-exportPackage", "Assets/com.sap.ec.unity", outputFile.absolutePath
            )
        }
        logger.lifecycle("Exported: ${outputFile.absolutePath}")
    }
}

// -----------------------------------------------------------------------------
// Task registrations
// -----------------------------------------------------------------------------

val stageShimFrameworks = tasks.register<StageShimFrameworksTask>("stageShimFrameworks") {
    description = "Symlink both Kotlin frameworks into shim/.build/frameworks for xcodebuild's FRAMEWORK_SEARCH_PATHS."
    group = "unity"
    dependsOn(engagementSdkFrameworkTask, unityKotlinFrameworkTask)
    mainFramework.set(engagementSdkFrameworkDir)
    unityKotlinFramework.set(unityKotlinFrameworkDir)
    stageDir.set(shimFrameworksStage)
}

val assembleUnityShim = tasks.register<AssembleShimTask>("assembleUnityShim") {
    description = "Run xcodegen + xcodebuild to produce EngagementCloudSDKUnity.bundle."
    group = "unity"
    dependsOn(stageShimFrameworks)
    shimSrcDir.set(shimDir.dir("src"))
    projectYml.set(shimDir.file("project.yml"))
    frameworksStage.set(shimFrameworksStage)
    wrapperVersion.set(upmVersionProvider)
    bundleDir.set(shimBundleDir)
}

abstract class CopyNativePluginsTask : DefaultTask() {
    @get:Inject abstract val execOperations: ExecOperations

    @get:InputDirectory abstract val mainFramework: DirectoryProperty
    @get:InputDirectory abstract val unityKotlinFramework: DirectoryProperty
    @get:InputDirectory abstract val shimBundle: DirectoryProperty
    @get:OutputDirectory abstract val pluginsDir: DirectoryProperty

    @TaskAction
    fun run() {
        val target = pluginsDir.get().asFile
        target.mkdirs()
        // Wipe previous framework/bundle artifacts but keep the .gitkeep so
        // git tracks the empty directory.
        target.listFiles()?.forEach { f ->
            if (f.name == ".gitkeep") return@forEach
            if (f.name.endsWith(".framework") || f.name.endsWith(".bundle") || f.name.endsWith(".dSYM")) {
                f.deleteRecursively()
            }
        }
        // `cp -R` preserves symlinks inside the framework (the Kotlin/Native
        // framework's Current -> Versions/A symlink), which the Gradle Copy
        // task's default handling breaks. Use rsync for a semantics-preserving
        // recursive copy.
        listOf(
            mainFramework.get().asFile to File(target, "EngagementCloudSDK.framework"),
            unityKotlinFramework.get().asFile to File(target, "EngagementCloudSDKUnityKotlin.framework"),
            shimBundle.get().asFile to File(target, "EngagementCloudSDKUnity.bundle"),
        ).forEach { (src, dst) ->
            if (dst.exists()) dst.deleteRecursively()
            execOperations.exec {
                commandLine("cp", "-R", src.absolutePath, dst.absolutePath)
            }
        }
    }
}

val copyUnityNativePlugins = tasks.register<CopyNativePluginsTask>("copyUnityNativePlugins") {
    description = "Copy the framework(s) + shim bundle into com.sap.ec.unity/Plugins/macOS."
    group = "unity"
    dependsOn(assembleUnityShim)
    mainFramework.set(engagementSdkFrameworkDir)
    unityKotlinFramework.set(unityKotlinFrameworkDir)
    shimBundle.set(shimBundleDir)
    pluginsDir.set(pluginsMacosDir)
}

val packUnityUpm = tasks.register<PackUpmTask>("packUnityUpm") {
    description = "Tarball the UPM package into dist/com.sap.ec.unity-<version>.tgz."
    group = "unity"
    dependsOn(copyUnityNativePlugins)
    upmPackageDir.set(upmRoot)
    outputTarball.set(
        rootProject.layout.projectDirectory.file("dist/com.sap.ec.unity-${upmVersionProvider.get()}.tgz")
    )
}

@Suppress("unused")
val exportUnityPackage = tasks.register<ExportUnityPackageTask>("exportUnityPackage") {
    description = "Produce a legacy .unitypackage via Unity CLI. Skipped if UNITY_PATH is unset."
    group = "unity"
    dependsOn(copyUnityNativePlugins)
    upmPackageDir.set(upmRoot)
    version.set(upmVersionProvider)
    distDir.set(rootProject.layout.projectDirectory.dir("dist"))
}
