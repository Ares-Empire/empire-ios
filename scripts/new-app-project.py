#!/usr/bin/env python3
"""Create a new Empire iPhone app project: <Name>/<Name>.xcodeproj with an app target and a test target.

    python3 scripts/new-app-project.py Empire de.ares-empire.empire "Ares Empire"

What every Empire app gets (see CLAUDE.md → Setup state):
- folder-synchronized groups: <Name>/ (app), <Name>Tests/ (tests), ../Shared/ (the shared login, network layer,
  fonts), so new Swift files need no project edits;
- iOS 26+, Swift 6 with MainActor default isolation, iPhone only, portrait;
- <Name>.entitlements with the shared App Group and Keychain group (one login for all Empire apps);
- <Name>/Info.plist merged with the generated one (excluded from the folder's resources), with
  ITSAppUsesNonExemptEncryption = NO (only HTTPS);
- <Name>/PrivacyInfo.xcprivacy, Apple's privacy manifest with what every Empire app collects (the login, the
  account id, the support form) and the App Group defaults; add the app's own data (docs/APP-STORE.md);
- English and German (CLAUDE.md → Languages): `de` among the known regions, tests run in English (en/GB);
- a shared scheme with the tests.
It only creates files that do not exist yet and refuses to overwrite a project.
"""
import hashlib
import os
import sys

if len(sys.argv) != 4:
    sys.exit(__doc__)
NAME, BUNDLE, DISPLAY = sys.argv[1], sys.argv[2], sys.argv[3]
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", NAME)
PROJ = os.path.join(ROOT, NAME + ".xcodeproj")
if os.path.exists(PROJ):
    sys.exit(f"{PROJ} already exists; edit it instead of regenerating.")


def oid(key):
    return hashlib.md5(f"{NAME.lower()}-{key}".encode()).hexdigest()[:24].upper()


I = {k: oid(k) for k in """PROJECT MAINGROUP PRODUCTS APPGROUP TESTGROUP SHARED APPEXC APPPRODUCT TESTPRODUCT APPTARGET
TESTTARGET APPSOURCES APPFW APPRES TESTSOURCES TESTFW TESTRES TESTPROXY TESTDEP PROJLIST PROJDEBUG PROJRELEASE
APPLIST APPDEBUG APPRELEASE TESTLIST TESTDEBUG TESTRELEASE""".split()}

common = {"ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
          "COPY_PHASE_STRIP": "NO", "CURRENT_PROJECT_VERSION": "1", "ENABLE_STRICT_OBJC_MSGSEND": "YES",
          "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
          "IPHONEOS_DEPLOYMENT_TARGET": "26.0", "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES", "MARKETING_VERSION": "0.1",
          "SDKROOT": "iphoneos", "SWIFT_APPROACHABLE_CONCURRENCY": "YES", "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
          "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES", "SWIFT_VERSION": "6.0"}
proj_debug = {**common, "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_OPTIMIZATION_LEVEL": "0",
              "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
              "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"'}
proj_release = {**common, "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"', "SWIFT_COMPILATION_MODE": "wholemodule",
                "VALIDATE_PRODUCT": "YES"}
app = {"ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
       "CODE_SIGN_ENTITLEMENTS": f"{NAME}.entitlements", "CODE_SIGN_STYLE": "Automatic", "ENABLE_PREVIEWS": "YES",
       "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_FILE": f"{NAME}/Info.plist",
       "INFOPLIST_KEY_CFBundleDisplayName": f'"{DISPLAY}"', "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
       "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
       "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
       "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
       "PRODUCT_BUNDLE_IDENTIFIER": f'"{BUNDLE}"', "PRODUCT_NAME": '"$(TARGET_NAME)"', "SWIFT_EMIT_LOC_STRINGS": "YES",
       "TARGETED_DEVICE_FAMILY": "1"}
tests = {"BUNDLE_LOADER": '"$(TEST_HOST)"', "CODE_SIGN_STYLE": "Automatic", "GENERATE_INFOPLIST_FILE": "YES",
         "PRODUCT_BUNDLE_IDENTIFIER": f'"{BUNDLE}.tests"', "PRODUCT_NAME": '"$(TARGET_NAME)"', "SWIFT_EMIT_LOC_STRINGS": "NO",
         "TARGETED_DEVICE_FAMILY": "1",
         "TEST_HOST": f'"$(BUILT_PRODUCTS_DIR)/{NAME}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{NAME}"'}


def cfg(key, label, settings):
    body = "\n".join(f"\t\t\t\t{k} = {v};" for k, v in sorted(settings.items()))
    return (f"\t\t{I[key]} /* {label} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{body}\n"
            f"\t\t\t}};\n\t\t\tname = {label};\n\t\t}};\n")


def phase(key, isa, label):
    return (f"\t\t{I[key]} /* {label} */ = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n"
            f"\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")


def cfglist(key, what, debug, release):
    return (f"\t\t{I[key]} /* Build configuration list for {what} */ = {{\n\t\t\tisa = XCConfigurationList;\n"
            f"\t\t\tbuildConfigurations = (\n\t\t\t\t{I[debug]} /* Debug */,\n\t\t\t\t{I[release]} /* Release */,\n"
            f"\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")


def target(key, label, lst, phases, deps, groups, product, ptype):
    ph = "".join(f"\t\t\t\t{I[p]},\n" for p in phases)
    dp = "".join(f"\t\t\t\t{I[d]},\n" for d in deps)
    gr = "".join(f"\t\t\t\t{I[g]},\n" for g in groups)
    return (f"\t\t{I[key]} /* {label} */ = {{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {I[lst]};\n"
            f"\t\t\tbuildPhases = (\n{ph}\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n{dp}\t\t\t);\n"
            f"\t\t\tfileSystemSynchronizedGroups = (\n{gr}\t\t\t);\n\t\t\tname = {label};\n"
            f"\t\t\tpackageProductDependencies = (\n\t\t\t);\n\t\t\tproductName = {label};\n"
            f"\t\t\tproductReference = {I[product]};\n\t\t\tproductType = \"{ptype}\";\n\t\t}};\n")


def group(key, path, exceptions=None, name=None):
    exc = f"\t\t\texceptions = (\n\t\t\t\t{I[exceptions]},\n\t\t\t);\n" if exceptions else ""
    nm = f"\t\t\tname = {name};\n" if name else ""
    return (f"\t\t{I[key]} /* {name or path} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n{exc}{nm}"
            f"\t\t\tpath = {path};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")


T = NAME + "Tests"
pbx = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXContainerItemProxy section */
\t\t{I['TESTPROXY']} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {I['PROJECT']} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {I['APPTARGET']};
\t\t\tremoteInfo = {NAME};
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
\t\t{I['APPPRODUCT']} /* {NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{I['TESTPRODUCT']} /* {T}.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {T}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
\t\t{I['APPEXC']} /* Exceptions for "{NAME}" folder in "{NAME}" target */ = {{
\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;
\t\t\tmembershipExceptions = (
\t\t\t\tInfo.plist,
\t\t\t);
\t\t\ttarget = {I['APPTARGET']} /* {NAME} */;
\t\t}};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
{group('APPGROUP', NAME, exceptions='APPEXC')}{group('TESTGROUP', T)}{group('SHARED', '../Shared', name='Shared')}/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
{phase('APPFW', 'PBXFrameworksBuildPhase', 'Frameworks')}{phase('TESTFW', 'PBXFrameworksBuildPhase', 'Frameworks')}/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{I['MAINGROUP']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['APPGROUP']} /* {NAME} */,
\t\t\t\t{I['SHARED']} /* Shared */,
\t\t\t\t{I['TESTGROUP']} /* {T} */,
\t\t\t\t{I['PRODUCTS']} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['PRODUCTS']} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['APPPRODUCT']} /* {NAME}.app */,
\t\t\t\t{I['TESTPRODUCT']} /* {T}.xctest */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
{target('APPTARGET', NAME, 'APPLIST', ['APPSOURCES', 'APPFW', 'APPRES'], [], ['APPGROUP', 'SHARED'], 'APPPRODUCT', 'com.apple.product-type.application')}{target('TESTTARGET', T, 'TESTLIST', ['TESTSOURCES', 'TESTFW', 'TESTRES'], ['TESTDEP'], ['TESTGROUP'], 'TESTPRODUCT', 'com.apple.product-type.bundle.unit-test')}/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{I['PROJECT']} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2710;
\t\t\t\tLastUpgradeCheck = 2710;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{I['APPTARGET']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 27.1;
\t\t\t\t\t}};
\t\t\t\t\t{I['TESTTARGET']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 27.1;
\t\t\t\t\t\tTestTargetID = {I['APPTARGET']};
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {I['PROJLIST']};
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tde,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {I['MAINGROUP']};
\t\t\tminimizedProjectReferenceProxies = 1;
\t\t\tpreferredProjectObjectVersion = 77;
\t\t\tproductRefGroup = {I['PRODUCTS']} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{I['APPTARGET']} /* {NAME} */,
\t\t\t\t{I['TESTTARGET']} /* {T} */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{phase('APPRES', 'PBXResourcesBuildPhase', 'Resources')}{phase('TESTRES', 'PBXResourcesBuildPhase', 'Resources')}/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{phase('APPSOURCES', 'PBXSourcesBuildPhase', 'Sources')}{phase('TESTSOURCES', 'PBXSourcesBuildPhase', 'Sources')}/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t{I['TESTDEP']} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {I['APPTARGET']} /* {NAME} */;
\t\t\ttargetProxy = {I['TESTPROXY']} /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{cfg('PROJDEBUG', 'Debug', proj_debug)}{cfg('PROJRELEASE', 'Release', proj_release)}{cfg('APPDEBUG', 'Debug', app)}{cfg('APPRELEASE', 'Release', app)}{cfg('TESTDEBUG', 'Debug', tests)}{cfg('TESTRELEASE', 'Release', tests)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{cfglist('PROJLIST', f'PBXProject "{NAME}"', 'PROJDEBUG', 'PROJRELEASE')}{cfglist('APPLIST', f'PBXNativeTarget "{NAME}"', 'APPDEBUG', 'APPRELEASE')}{cfglist('TESTLIST', f'PBXNativeTarget "{T}"', 'TESTDEBUG', 'TESTRELEASE')}/* End XCConfigurationList section */
\t}};
\trootObject = {I['PROJECT']} /* Project object */;
}}
"""

ref = lambda key, name, product: (f'BuildableIdentifier = "primary" BlueprintIdentifier = "{I[key]}" '
                                  f'BuildableName = "{product}" BlueprintName = "{name}" ReferencedContainer = "container:{NAME}.xcodeproj"')
scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2710" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference {ref('APPTARGET', NAME, NAME + '.app')}></BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction language = "en" region = "GB" buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES" shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference skipped = "NO" parallelizable = "YES">
            <BuildableReference {ref('TESTTARGET', T, T + '.xctest')}></BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference {ref('APPTARGET', NAME, NAME + '.app')}></BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference {ref('APPTARGET', NAME, NAME + '.app')}></BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
"""

entitlements = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- One login for all Empire apps: the shared App Group and Keychain group (Shared/EmpireShared.swift). -->
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.de.ares-empire.shared</string>
	</array>
	<key>keychain-access-groups</key>
	<array>
		<string>$(AppIdentifierPrefix)de.ares-empire.shared</string>
	</array>
</dict>
</plist>
"""

info = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Merged with the generated Info.plist (GENERATE_INFOPLIST_FILE). Only what build settings cannot express. -->
<plist version="1.0">
<dict>
	<!-- The team prefix of the shared Keychain group (Shared/EmpireShared.swift). -->
	<key>AppIdentifierPrefix</key>
	<string>$(AppIdentifierPrefix)</string>
	<!-- Only standard HTTPS: exempt, so App Store Connect stops asking about encryption on every build. -->
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
	<!-- Launch on the app's own background instead of a white flash. -->
	<key>UILaunchScreen</key>
	<dict>
		<key>UIColorName</key>
		<string>LaunchBackground</string>
	</dict>
</dict>
</plist>
"""

# The Empire app's manifest: only what every app shares. A new app adds its own data types (docs/APP-STORE.md).
privacy = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Apple privacy manifest (the """ + DISPLAY + """ app). What it declares and why: ares-empire/docs/PRIVACY.md and
     docs/APP-STORE.md. Update it when the app sends something new or starts using another required-reason API
     (https://developer.apple.com/documentation/bundleresources/privacy-manifest-files). -->
<plist version="1.0">
<dict>
	<!-- No tracking: no analytics, ads or third-party SDKs; data goes only to the Empire's own servers. -->
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<!-- CA92.1: this app's own defaults (Shared/Language/LanguageSetting.swift: the app's language, the same
				     setting iOS keeps in Settings → Apps → the app → Language). -->
				<string>CA92.1</string>
				<!-- 1C8F.1: the shared App Group's defaults (Shared/EmpireShared.swift: the first-launch flag). -->
				<string>1C8F.1</string>
			</array>
		</dict>
	</array>
	<!-- Everything is linked to the account and used only to run the app. -->
	<key>NSPrivacyCollectedDataTypes</key>
	<array>
		<!-- Email address: the Empire login (Shared/Auth), kept by the account server. -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeEmailAddress</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<!-- User ID: the Empire account id; every request carries the login token that names it. -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeUserID</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<!-- Customer support: the Contact & support form (Shared/Support, brief E5): message, app and iOS version, language. -->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeCustomerSupport</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
"""

files = {
    os.path.join(PROJ, "project.pbxproj"): pbx,
    os.path.join(PROJ, "xcshareddata", "xcschemes", NAME + ".xcscheme"): scheme,
    os.path.join(ROOT, NAME + ".entitlements"): entitlements,
    os.path.join(ROOT, NAME, "Info.plist"): info,
    os.path.join(ROOT, NAME, "PrivacyInfo.xcprivacy"): privacy,
}
for path, text in files.items():
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if not os.path.exists(path):
        with open(path, "w") as f:
            f.write(text)
        print("created", os.path.relpath(path, os.path.join(ROOT, "..")))
