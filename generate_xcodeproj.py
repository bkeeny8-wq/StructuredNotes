#!/usr/bin/env python3
"""Generate StructuredNotesDesk.xcodeproj with Framework + Example app targets."""

from __future__ import annotations

import os
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJ = ROOT / "StructuredNotesDesk.xcodeproj"
PROJ.mkdir(exist_ok=True)

def uid() -> str:
    return uuid.uuid4().hex[:24].upper()

# Stable-ish IDs for readability / diffs
IDS = {
    "project": uid(),
    "framework_target": uid(),
    "app_target": uid(),
    "framework_product": uid(),
    "app_product": uid(),
    "sources_group": uid(),
    "framework_group": uid(),
    "example_group": uid(),
    "products_group": uid(),
    "assets_ref": uid(),
    "framework_sources": uid(),
    "framework_frameworks": uid(),
    "framework_resources": uid(),
    "framework_headers": uid(),
    "app_sources": uid(),
    "app_frameworks": uid(),
    "app_resources": uid(),
    "project_config_list": uid(),
    "framework_config_list": uid(),
    "app_config_list": uid(),
    "project_debug": uid(),
    "project_release": uid(),
    "framework_debug": uid(),
    "framework_release": uid(),
    "app_debug": uid(),
    "app_release": uid(),
    "framework_dep": uid(),
    "embed_phase": uid(),
    "copy_framework": uid(),
}

framework_files = [
    "Models.swift",
    "MarketData.swift",
    "PricingEngine.swift",
    "Components.swift",
    "DeskView.swift",
]

header_name = "StructuredNotesDesk.h"

file_ids = {name: uid() for name in framework_files}
file_ids[header_name] = uid()
file_ids["StructuredNotesDeskApp.swift"] = uid()
file_ids["Info.plist"] = uid()

# Build file IDs (PBXBuildFile)
bf = {name: uid() for name in framework_files}
bf["app_main"] = uid()
bf["link_framework"] = uid()
bf["embed_framework"] = uid()
bf["header"] = uid()
bf["assets"] = uid()

framework_build_files = "\n".join(
    f"\t\t{bf[n]} /* {n} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ids[n]} /* {n} */; }};"
    for n in framework_files
)
framework_build_files += f"\n\t\t{bf['header']} /* {header_name} in Headers */ = {{isa = PBXBuildFile; fileRef = {file_ids[header_name]} /* {header_name} */; settings = {{ATTRIBUTES = (Public, ); }}; }};"

file_refs = "\n".join(
    f"\t\t{file_ids[n]} /* {n} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {n}; sourceTree = \"<group>\"; }};"
    for n in framework_files
)
file_refs += f"\n\t\t{file_ids[header_name]} /* {header_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = {header_name}; sourceTree = \"<group>\"; }};"

framework_source_children = "\n".join(f"\t\t\t\t{file_ids[n]} /* {n} */," for n in framework_files)
framework_source_children += f"\n\t\t\t\t{file_ids[header_name]} /* {header_name} */,"
framework_sources_build = "\n".join(f"\t\t\t\t{bf[n]} /* {n} in Sources */," for n in framework_files)

pbxproj = f'''// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{framework_build_files}
		{bf["app_main"]} /* StructuredNotesDeskApp.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ids["StructuredNotesDeskApp.swift"]} /* StructuredNotesDeskApp.swift */; }};
		{bf["link_framework"]} /* StructuredNotesDesk.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {IDS["framework_product"]} /* StructuredNotesDesk.framework */; }};
		{bf["embed_framework"]} /* StructuredNotesDesk.framework in Embed Frameworks */ = {{isa = PBXBuildFile; fileRef = {IDS["framework_product"]} /* StructuredNotesDesk.framework */; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }}; }};
		{bf["assets"]} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {IDS["assets_ref"]} /* Assets.xcassets */; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{IDS["framework_dep"]} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {IDS["project"]} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {IDS["framework_target"]};
			remoteInfo = StructuredNotesDesk;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		{IDS["embed_phase"]} /* Embed Frameworks */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 10;
			files = (
				{bf["embed_framework"]} /* StructuredNotesDesk.framework in Embed Frameworks */,
			);
			name = "Embed Frameworks";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
{file_refs}
		{file_ids["StructuredNotesDeskApp.swift"]} /* StructuredNotesDeskApp.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StructuredNotesDeskApp.swift; sourceTree = "<group>"; }};
		{file_ids["Info.plist"]} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
		{IDS["assets_ref"]} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};
		{IDS["framework_product"]} /* StructuredNotesDesk.framework */ = {{isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = StructuredNotesDesk.framework; sourceTree = BUILT_PRODUCTS_DIR; }};
		{IDS["app_product"]} /* StructuredNotesDeskExample.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = StructuredNotesDeskExample.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{IDS["framework_frameworks"]} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{IDS["app_frameworks"]} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{bf["link_framework"]} /* StructuredNotesDesk.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{IDS["sources_group"]} = {{
			isa = PBXGroup;
			children = (
				{IDS["framework_group"]} /* StructuredNotesDesk */,
				{IDS["example_group"]} /* Example */,
				{IDS["products_group"]} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{IDS["framework_group"]} /* StructuredNotesDesk */ = {{
			isa = PBXGroup;
			children = (
{framework_source_children}
			);
			name = StructuredNotesDesk;
			path = Sources/StructuredNotesDesk;
			sourceTree = "<group>";
		}};
		{IDS["example_group"]} /* Example */ = {{
			isa = PBXGroup;
			children = (
				{file_ids["StructuredNotesDeskApp.swift"]} /* StructuredNotesDeskApp.swift */,
				{IDS["assets_ref"]} /* Assets.xcassets */,
				{file_ids["Info.plist"]} /* Info.plist */,
			);
			path = Example;
			sourceTree = "<group>";
		}};
		{IDS["products_group"]} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{IDS["framework_product"]} /* StructuredNotesDesk.framework */,
				{IDS["app_product"]} /* StructuredNotesDeskExample.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXHeadersBuildPhase section */
		{IDS["framework_headers"]} /* Headers */ = {{
			isa = PBXHeadersBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{bf["header"]} /* {header_name} in Headers */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXHeadersBuildPhase section */

/* Begin PBXNativeTarget section */
		{IDS["framework_target"]} /* StructuredNotesDesk */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {IDS["framework_config_list"]} /* Build configuration list for PBXNativeTarget "StructuredNotesDesk" */;
			buildPhases = (
				{IDS["framework_headers"]} /* Headers */,
				{IDS["framework_sources"]} /* Sources */,
				{IDS["framework_frameworks"]} /* Frameworks */,
				{IDS["framework_resources"]} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = StructuredNotesDesk;
			productName = StructuredNotesDesk;
			productReference = {IDS["framework_product"]} /* StructuredNotesDesk.framework */;
			productType = "com.apple.product-type.framework";
		}};
		{IDS["app_target"]} /* StructuredNotesDeskExample */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {IDS["app_config_list"]} /* Build configuration list for PBXNativeTarget "StructuredNotesDeskExample" */;
			buildPhases = (
				{IDS["app_sources"]} /* Sources */,
				{IDS["app_frameworks"]} /* Frameworks */,
				{IDS["app_resources"]} /* Resources */,
				{IDS["embed_phase"]} /* Embed Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				{IDS["copy_framework"]} /* PBXTargetDependency */,
			);
			name = StructuredNotesDeskExample;
			productName = StructuredNotesDeskExample;
			productReference = {IDS["app_product"]} /* StructuredNotesDeskExample.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{IDS["project"]} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2600;
				LastUpgradeCheck = 2600;
				TargetAttributes = {{
					{IDS["framework_target"]} = {{
						CreatedOnToolsVersion = 26.0;
					}};
					{IDS["app_target"]} = {{
						CreatedOnToolsVersion = 26.0;
					}};
				}};
			}};
			buildConfigurationList = {IDS["project_config_list"]} /* Build configuration list for PBXProject "StructuredNotesDesk" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {IDS["sources_group"]};
			productRefGroup = {IDS["products_group"]} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{IDS["framework_target"]} /* StructuredNotesDesk */,
				{IDS["app_target"]} /* StructuredNotesDeskExample */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{IDS["framework_resources"]} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{IDS["app_resources"]} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{bf["assets"]} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{IDS["framework_sources"]} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{framework_sources_build}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{IDS["app_sources"]} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{bf["app_main"]} /* StructuredNotesDeskApp.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{IDS["copy_framework"]} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {IDS["framework_target"]} /* StructuredNotesDesk */;
			targetProxy = {IDS["framework_dep"]} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		{IDS["project_debug"]} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			}};
			name = Debug;
		}};
		{IDS["project_release"]} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_VERSION = 5.0;
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{IDS["framework_debug"]} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				BUILD_LIBRARY_FOR_DISTRIBUTION = NO;
				CURRENT_PROJECT_VERSION = 1;
				DEFINES_MODULE = YES;
				DYLIB_COMPATIBILITY_VERSION = 1;
				DYLIB_CURRENT_VERSION = 1;
				DYLIB_INSTALL_NAME_BASE = "@rpath";
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				INSTALL_PATH = "$(LOCAL_LIBRARY_DIR)/Frameworks";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@loader_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.structurednotes.StructuredNotesDesk;
				PRODUCT_MODULE_NAME = StructuredNotesDesk;
				PRODUCT_NAME = "$(TARGET_NAME:c99extidentifier)";
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_INSTALL_OBJC_HEADER = NO;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				VERSIONING_SYSTEM = "apple-generic";
				VERSION_INFO_PREFIX = "";
			}};
			name = Debug;
		}};
		{IDS["framework_release"]} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				BUILD_LIBRARY_FOR_DISTRIBUTION = NO;
				CURRENT_PROJECT_VERSION = 1;
				DEFINES_MODULE = YES;
				DYLIB_COMPATIBILITY_VERSION = 1;
				DYLIB_CURRENT_VERSION = 1;
				DYLIB_INSTALL_NAME_BASE = "@rpath";
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				INSTALL_PATH = "$(LOCAL_LIBRARY_DIR)/Frameworks";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@loader_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.structurednotes.StructuredNotesDesk;
				PRODUCT_MODULE_NAME = StructuredNotesDesk;
				PRODUCT_NAME = "$(TARGET_NAME:c99extidentifier)";
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_INSTALL_OBJC_HEADER = NO;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				VERSIONING_SYSTEM = "apple-generic";
				VERSION_INFO_PREFIX = "";
			}};
			name = Release;
		}};
		{IDS["app_debug"]} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = Example/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = "Structured Notes";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.structurednotes.StructuredNotesDeskExample;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
		{IDS["app_release"]} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = Example/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = "Structured Notes";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.structurednotes.StructuredNotesDeskExample;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{IDS["project_config_list"]} /* Build configuration list for PBXProject "StructuredNotesDesk" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{IDS["project_debug"]} /* Debug */,
				{IDS["project_release"]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{IDS["framework_config_list"]} /* Build configuration list for PBXNativeTarget "StructuredNotesDesk" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{IDS["framework_debug"]} /* Debug */,
				{IDS["framework_release"]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{IDS["app_config_list"]} /* Build configuration list for PBXNativeTarget "StructuredNotesDeskExample" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{IDS["app_debug"]} /* Debug */,
				{IDS["app_release"]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {IDS["project"]} /* Project object */;
}}
'''

(PROJ / "project.pbxproj").write_text(pbxproj)
print(f"Wrote {PROJ / 'project.pbxproj'}")
