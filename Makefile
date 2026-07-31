.PHONY: build build-pipeline build-android build-ios build-ios-all-archtypes build-js-html build-web check-env clean create-apks help lint pipeline-android pipeline-js pipeline-ios prepare-release prepare-local-spm publish-android publish-ios-spm publish-npm release release-locally stage-maven-central test test-android test-android-firebase test-ios test-sdk-loader test-web add-privacy-manifest-to-frameworks assemble-npm-package fix-npm-typescript-brand-fields unity-shim unity-copy unity-package unity-unitypackage unity-clean unity-release unity-release-dryrun
.DEFAULT_GOAL := help
SHELL := /bin/bash

ifneq (,$(wildcard .env))
include .env
export
endif

REQUIRED_VARS := $(shell cat .env.example | sed 's/=.*//' | xargs)
check-env:
	@MISSING_VARS=""; \
	for var in $(REQUIRED_VARS); do \
		if [ -z "$${!var+x}" ]; then \
			MISSING_VARS="$$MISSING_VARS $$var"; \
		fi; \
	done; \
	if [ -n "$$MISSING_VARS" ]; then \
		echo "Missing environment variables:$$MISSING_VARS"; \
		echo "Please set them in your .env file or as system environment variables. Check https://secret.emarsys.net/cred/detail/18243/"; \
		exit 1; \
	fi
help:
	@echo "Available targets:"
	@echo "  build-android               - Build Android artifacts"
	@echo "  build-ios                   - Build iOS artifacts"
	@echo "  build-js-html               - Build JS artifacts"
	@echo "  lint                        - Run lint"
	@echo "  test                        - Run all tests"
	@echo "  prepare-local-spm           - Build local iOS frameworks for iosApp testing (no Privacy Manifest)"
	@echo "  add-privacy-manifest-to-frameworks - Add Privacy Manifest to release XCFrameworks (run after building release frameworks)"
	@echo "  publish-maven               - Publish to GitHub Packages (Maven)"
	@echo "  publish-npm                 - Publish to GitHub Packages (NPM)"
	@echo "  publish-ios-spm             - Publish iOS SPM"
	@echo "  unity-shim                  - Build the Unity native shim bundle"
	@echo "  unity-copy                  - Stage frameworks + bundle into com.sap.ec.unity/Plugins/macOS"
	@echo "  unity-package               - Build the UPM tarball (dist/com.sap.ec.unity-<version>.tgz)"
	@echo "  unity-unitypackage          - Also export a legacy .unitypackage (requires UNITY_PATH env var)"
	@echo "  unity-clean                 - Clean Unity plugin build outputs"
	@echo "  unity-release-dryrun        - Print what unity-release would do without doing it"
	@echo "  unity-release               - Build + create a GitHub release tagged unity-v<version>"

clean-dist:
	@rm -rf dist

build: check-env
	@./gradlew assemble

build-pipeline: check-env
	@./gradlew assemble

clean: check-env
	@./gradlew clean

create-apks: check-env
	@./gradlew :androidApp:assembleRelease

test: check-env test-android test-web test-sdk-loader test-ios

build-js-html: check-env
	@./gradlew :engagement-cloud-sdk:jsBrowserDistribution \
		-Pjs.variant=html \
		-x :composeApp:jsBrowserDistribution

build-web: build-js-html

test-web: check-env
	@./gradlew :engagement-cloud-sdk:jsBrowserTest \
		-Pjs.variant=html \
		-x :composeApp:jsBrowserTest

test-sdk-loader: check-env
	@./gradlew :engagement-cloud-sdk:jsBrowserTest \
		-Pjs.variant=html \
		-x :composeApp:jsBrowserTest \
		--tests com.sap.ec.mobileengage.WebSdkLoaderTest

build-android: check-env
	@./gradlew \
		:engagement-cloud-sdk:assembleAndroidMain \
		:engagement-cloud-sdk-android-fcm:assembleRelease \
		:engagement-cloud-sdk-android-hms:assembleRelease

test-android: check-env
	@./gradlew \
		:engagement-cloud-sdk:testAndroidHostTest \
		:engagement-cloud-sdk:connectedAndroidDeviceTest \
		:engagement-cloud-sdk-android-fcm:testDebugUnitTest \
		:engagement-cloud-sdk-android-hms:testDebugUnitTest

build-ios-all-archtypes: check-env
	@./gradlew \
		:engagement-cloud-sdk:assembleEngagementCloudSDKReleaseXCFramework \
		:ios-notification-service:assembleEngagementCloudNotificationServiceReleaseXCFramework

build-ios: check-env
	@./gradlew :engagement-cloud-sdk:iosArm64Binaries

test-ios: check-env
	@./gradlew :engagement-cloud-sdk:iosX64Test

test-android-firebase: check-env
	@gcloud firebase test android run \
		--type instrumentation \
		--app engagement-cloud-sdk/build/outputs/apk/debug/engagement-cloud-sdk-debug.apk \
		--test engagement-cloud-sdk/build/outputs/apk/androidTest/debug/engagement-cloud-sdk-debug-androidTest.apk \
		--device model=Pixel3,version=30,locale=en,orientation=portrait

lint: check-env
	@./gradlew \
		:engagement-cloud-sdk-android-fcm:lintRelease \
		:engagement-cloud-sdk-android-hms:lintRelease

prepare-local-spm: check-env
	@./gradlew \
		-PENABLE_PUBLISHING=true \
		spmDevBuild && \
		cp -f "./spmLocalRelease/Package.swift" "./Package.swift" && \
		echo "Local Swift Package is prepared."

add-privacy-manifest-to-frameworks:
	@echo "Adding Privacy Manifest to release XCFrameworks..."
	@PRIVACY_MANIFEST="engagement-cloud-sdk/src/iosMain/resources/PrivacyInfo.xcprivacy"; \
	if [ ! -f "$$PRIVACY_MANIFEST" ]; then \
		echo "Error: Privacy Manifest not found at $$PRIVACY_MANIFEST"; \
		exit 1; \
	fi; \
	find engagement-cloud-sdk/build/XCFrameworks/release -name "EngagementCloudSDK.framework" -type d | while read framework; do \
		echo "  → $$framework"; \
		cp "$$PRIVACY_MANIFEST" "$$framework/"; \
	done; \
	echo "Privacy Manifest added to all framework variants"

publish-maven: check-env
	@./gradlew \
		-PENABLE_PUBLISHING=true \
		:engagement-cloud-sdk:publishAllPublicationsToGitHubPackagesRepository \
		:engagement-cloud-sdk-android-fcm:publishMavenPublicationToGitHubPackagesRepository \
		:engagement-cloud-sdk-android-hms:publishMavenPublicationToGitHubPackagesRepository

publish-maven-ios: check-env
	@./gradlew \
		-PENABLE_PUBLISHING=true \
		:engagement-cloud-sdk:publishIosArm64PublicationToGitHubPackagesRepository \
		:engagement-cloud-sdk:publishIosX64PublicationToGitHubPackagesRepository \
		:engagement-cloud-sdk:publishIosSimulatorArm64PublicationToGitHubPackagesRepository \
		:ios-notification-service:publishIosArm64PublicationToGitHubPackagesRepository \
		:ios-notification-service:publishIosX64PublicationToGitHubPackagesRepository \
		:ios-notification-service:publishIosSimulatorArm64PublicationToGitHubPackagesRepository \
		:ios-notification-service:publishKotlinMultiplatformPublicationToGitHubPackagesRepository

publish-npm: check-env
	@cd dist/npm && npm publish --registry https://npm.pkg.github.com

publish-ios-spm: check-env
	@./gradlew kmmBridgePublish \
		-PNATIVE_BUILD_TYPE='RELEASE' \
		-PGITHUB_ARTIFACT_RELEASE_ID=$(GITHUB_ARTIFACT_RELEASE_ID) \
		-PGITHUB_PUBLISH_TOKEN=$(GITHUB_TOKEN) \
		-PGITHUB_REPO=$(GITHUB_REPO) \
		-PENABLE_PUBLISHING=true \
		--no-daemon

prepare-release: check-env
	@./gradlew base64EnvToFile -PpropertyName=SONATYPE_SIGNING_SECRET_KEY_RING_FILE_BASE64 -Pfile=./secring.asc.gpg

release: check-env prepare-release
	@./gradlew assembleRelease publishToMavenCentral -PPROMOTE_TO_MAVEN_CENTRAL=true

release-locally: check-env prepare-release
	@./gradlew assembleRelease publishToMavenLocal -PPROMOTE_TO_MAVEN_CENTRAL=true

stage-maven-central: check-env prepare-release
	@./gradlew publishToMavenCentral \
		-PPROMOTE_TO_MAVEN_CENTRAL=true \
		-PENABLE_PUBLISHING=true \
		--no-daemon

pipeline-android: check-env
	@./gradlew \
		:engagement-cloud-sdk:assembleAndroidMain \
		:engagement-cloud-sdk-android-fcm:assembleRelease \
		:engagement-cloud-sdk-android-hms:assembleRelease \
		:engagement-cloud-sdk-android-fcm:lintRelease \
		:engagement-cloud-sdk-android-hms:lintRelease \
		:engagement-cloud-sdk:testAndroidHostTest \
		:engagement-cloud-sdk-android-fcm:testDebugUnitTest \
		:engagement-cloud-sdk-android-hms:testDebugUnitTest \
		$(if $(filter true,$(PUBLISH)), \
			:engagement-cloud-sdk:publishKotlinMultiplatformPublicationToGitHubPackagesRepository \
			:engagement-cloud-sdk:publishAndroidPublicationToGitHubPackagesRepository \
			:engagement-cloud-sdk:publishJsPublicationToGitHubPackagesRepository \
			:engagement-cloud-sdk:publishIosArm64PublicationToGitHubPackagesRepository \
			:engagement-cloud-sdk:publishIosX64PublicationToGitHubPackagesRepository \
			:engagement-cloud-sdk:publishIosSimulatorArm64PublicationToGitHubPackagesRepository \
			:engagement-cloud-sdk-android-fcm:publishMavenPublicationToGitHubPackagesRepository \
			:engagement-cloud-sdk-android-hms:publishMavenPublicationToGitHubPackagesRepository) \
		-Pjs.variant=canvas \
		-PENABLE_PUBLISHING=$(PUBLISH) \
		--no-daemon

pipeline-js: check-env
	@./gradlew \
		:web-push-service-worker:jsBrowserDistribution \
		:engagement-cloud-sdk:jsBrowserDistribution \
		:engagement-cloud-sdk:jsBrowserTest \
		-Pjs.variant=html \
		-x :composeApp:jsBrowserDistribution \
		-x :composeApp:jsBrowserTest \
		--no-daemon

fix-npm-typescript-brand-fields:
	@echo "Fixing TypeScript brand fields in .d.mts (making __doNotUseOrImplementIt optional)..."
	@mkdir -p dist/npm
	@sed -e 's/readonly __doNotUseOrImplementIt/__doNotUseOrImplementIt?/g' \
		engagement-cloud-sdk/build/compileSync/js/main/productionExecutable/kotlin/EngagementCloudSDK-engagement-cloud-sdk.d.mts \
		> dist/npm/EngagementCloudSDK-engagement-cloud-sdk.d.mts

assemble-npm-package: fix-npm-typescript-brand-fields
	@cp engagement-cloud-sdk/build/compileSync/js/main/productionExecutable/kotlin/EngagementCloudSDK-engagement-cloud-sdk.mjs dist/npm/ && \
	cp engagement-cloud-sdk/build/compileSync/js/main/productionExecutable/kotlin/EngagementCloudSDK-engagement-cloud-sdk.mjs.map dist/npm/ && \
	cp engagement-cloud-sdk/build/tmp/jsPublicPackageJson/package.json dist/npm/ && \
	cp README.md dist/npm/

pipeline-ios: check-env
	@./gradlew \
		:engagement-cloud-sdk:iosX64Test \
		$(if $(filter true,$(PUBLISH)), \
			:engagement-cloud-sdk:assembleEngagementCloudSDKReleaseXCFramework \
			:ios-notification-service:assembleEngagementCloudNotificationServiceReleaseXCFramework) \
		-PNATIVE_BUILD_TYPE='$(if $(filter true,$(PUBLISH)),RELEASE,DEBUG)' \
		$(if $(filter true,$(PUBLISH)),-PENABLE_PUBLISHING=true) \
		--no-daemon
# Unity plugin (macOS Apple-Silicon only) — see Unity-sdk-phase2-plan.md
# Requires: xcodegen (brew install xcodegen). Unity CLI only needed for
# `unity-unitypackage` (UNITY_PATH env var; skipped silently if unset).

unity-shim:
	@./gradlew :unity-plugin:assembleUnityShim

unity-copy:
	@./gradlew :unity-plugin:copyUnityNativePlugins

unity-package:
	@./gradlew :unity-plugin:packUnityUpm

unity-unitypackage:
	@./gradlew :unity-plugin:exportUnityPackage

unity-clean:
	@rm -rf unity-plugin/shim/.build unity-plugin/shim/EngagementCloudSDKUnity.xcodeproj \
	        unity-plugin/shim/EngagementCloudSDKUnity-Info.plist \
	        unity-plugin/com.sap.ec.unity/Plugins/macOS/*.framework \
	        unity-plugin/com.sap.ec.unity/Plugins/macOS/*.bundle \
	        unity-plugin/com.sap.ec.unity/Plugins/macOS/*.dSYM \
	        dist/com.sap.ec.unity-*.tgz dist/EngagementCloud-*.unitypackage

# -----------------------------------------------------------------------------
# Unity plugin release publishing.
#
# Reads the version from unity-plugin/com.sap.ec.unity/package.json, builds the
# UPM tarball (and .unitypackage if UNITY_PATH is set), then invokes `gh` to
# create a GitHub release tagged `unity-v<version>` and upload the artifacts.
#
# Requirements:
#   - gh CLI installed (brew install gh) and authenticated (`gh auth login`).
#   - Working tree must be clean (no uncommitted changes) and on `main`.
#   - The tag `unity-v<version>` must not already exist.
#
# Usage:
#   make unity-release-dryrun   # preview
#   make unity-release          # actually publishes
#
# Bump the version in unity-plugin/com.sap.ec.unity/package.json before
# running these — the tag comes from that file, so a stale version means
# a stale tag.

UNITY_VERSION := $(shell sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' unity-plugin/com.sap.ec.unity/package.json)
UNITY_TAG := unity-v$(UNITY_VERSION)
UNITY_TGZ := dist/com.sap.ec.unity-$(UNITY_VERSION).tgz
UNITY_UNITYPACKAGE := dist/EngagementCloud-$(UNITY_VERSION).unitypackage

unity-release-dryrun:
	@echo "Version (from package.json): $(UNITY_VERSION)"
	@echo "Tag:                         $(UNITY_TAG)"
	@echo "Tarball:                     $(UNITY_TGZ)"
	@echo "unitypackage (optional):     $(UNITY_UNITYPACKAGE)"
	@echo ""
	@echo "Would run:"
	@echo "  1. make unity-package"
	@if [ -n "$$UNITY_PATH" ]; then \
		echo "  2. make unity-unitypackage  (UNITY_PATH is set)"; \
	else \
		echo "  2. skip unity-unitypackage  (UNITY_PATH not set)"; \
	fi
	@echo "  3. gh release create $(UNITY_TAG) $(UNITY_TGZ) [+ .unitypackage if built]"
	@echo ""
	@echo "Preflight checks:"
	@command -v gh >/dev/null 2>&1 && echo "  gh: OK" || echo "  gh: MISSING (brew install gh)"
	@gh auth status >/dev/null 2>&1 && echo "  gh auth: OK" || echo "  gh auth: NOT AUTHENTICATED (run: gh auth login)"
	@[ -z "$$(git status --porcelain --untracked-files=no)" ] && echo "  working tree: clean (ignoring untracked files)" || echo "  working tree: DIRTY (commit first)"
	@BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
		[ "$$BRANCH" = "main" ] && echo "  branch: main" || echo "  branch: $$BRANCH (unusual — usually release from main)"
	@if git rev-parse "$(UNITY_TAG)" >/dev/null 2>&1; then \
		echo "  tag $(UNITY_TAG): ALREADY EXISTS (bump version in package.json)"; \
	else \
		echo "  tag $(UNITY_TAG): available"; \
	fi

unity-release:
	@command -v gh >/dev/null 2>&1 || { echo "gh not found. Install with: brew install gh" >&2; exit 1; }
	@gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated. Run: gh auth login" >&2; exit 1; }
	@[ -z "$$(git status --porcelain --untracked-files=no)" ] || { echo "Working tree has uncommitted changes (tracked files). Commit or stash first." >&2; exit 1; }
	@if git rev-parse "$(UNITY_TAG)" >/dev/null 2>&1; then \
		echo "Tag $(UNITY_TAG) already exists. Bump the version in unity-plugin/com.sap.ec.unity/package.json first." >&2; \
		exit 1; \
	fi
	@echo "==> Building UPM tarball..."
	@$(MAKE) --no-print-directory unity-package
	@if [ -n "$$UNITY_PATH" ]; then \
		echo "==> Building .unitypackage (UNITY_PATH is set)..."; \
		$(MAKE) --no-print-directory unity-unitypackage; \
	else \
		echo "==> Skipping .unitypackage (UNITY_PATH not set; only .tgz will be uploaded)"; \
	fi
	@[ -f "$(UNITY_TGZ)" ] || { echo "Expected $(UNITY_TGZ) after build, but it's missing." >&2; exit 1; }
	@echo "==> Creating GitHub release $(UNITY_TAG)..."
	@REL_ARGS="$(UNITY_TGZ)"; \
		if [ -f "$(UNITY_UNITYPACKAGE)" ]; then REL_ARGS="$$REL_ARGS $(UNITY_UNITYPACKAGE)"; fi; \
		gh release create "$(UNITY_TAG)" $$REL_ARGS \
			--title "SAP Engagement Cloud Unity Plugin $(UNITY_VERSION)" \
			--notes-file .github/release-notes/unity-plugin.md \
			--target $$(git rev-parse HEAD)
	@echo ""
	@echo "Released: https://github.com/emartech/engagement-cloud-unity-sdk/releases/tag/$(UNITY_TAG)"
