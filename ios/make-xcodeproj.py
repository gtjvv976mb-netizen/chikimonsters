#!/usr/bin/env python3
"""Generate ios/Chikoria.xcodeproj so the app can be opened and built.

    python3 ios/make-xcodeproj.py            # write the project
    python3 ios/make-xcodeproj.py --check    # parse and validate the existing one, write nothing

The Swift sources, the Info.plist and the asset catalog were written before there was any project
to put them in, so `ios/` held everything an iOS app needs except the one file Xcode opens. This
writes that file.

It is a generator rather than a committed blob-you-must-trust for two reasons. A `project.pbxproj`
is a graph of 24-character object IDs referring to each other, and a single wrong reference makes
Xcode refuse the project with no useful message — so the IDs here are derived from stable names
(a hash of the object's role), which makes the output deterministic and a diff between two runs
meaningful. And because this file was authored without a Mac to test on, `--check` parses the
result back and verifies that **every** referenced ID exists and every file on disk is actually in
a build phase. That is not the same as proving Xcode is happy, but it catches the whole class of
error that would otherwise waste your time.

Adding a Swift file later: drop it in `ios/Chikoria/` and re-run. Sources are discovered, not
listed.
"""

import hashlib
import plistlib
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
APP = "Chikoria"
BUNDLE_ID = "com.chikimonsters.Chikoria"
DEPLOYMENT_TARGET = "16.0"          # WKWebView + SwiftUI features used by ShellModel
MARKETING_VERSION = "1.0"
CURRENT_PROJECT_VERSION = "1"
SWIFT_VERSION = "5.0"


def oid(role: str) -> str:
	"""A stable 24-hex-character object ID derived from the object's role."""
	return hashlib.sha1(f"chikoria::{role}".encode()).hexdigest()[:24].upper()


def build_project() -> tuple[str, list[str], list[str]]:
	sources = sorted(p.name for p in (HERE / APP).glob("*.swift"))
	if not sources:
		raise SystemExit(f"error: no .swift files in {HERE / APP}")
	resources = [n for n in ("Assets.xcassets", "PrivacyInfo.xcprivacy") if (HERE / APP / n).exists()]

	# --- object ids -----------------------------------------------------------------------
	proj = oid("project")
	target = oid("target")
	product = oid("product")
	main_group = oid("group.main")
	app_group = oid("group.app")
	products_group = oid("group.products")
	sources_phase = oid("phase.sources")
	resources_phase = oid("phase.resources")
	frameworks_phase = oid("phase.frameworks")
	proj_cfg_list = oid("cfglist.project")
	target_cfg_list = oid("cfglist.target")
	proj_debug, proj_release = oid("cfg.project.debug"), oid("cfg.project.release")
	tgt_debug, tgt_release = oid("cfg.target.debug"), oid("cfg.target.release")
	plist_ref = oid("file.Info.plist")

	file_refs = {n: oid(f"file.{n}") for n in sources + resources}
	build_files = {n: oid(f"buildfile.{n}") for n in sources + resources}

	L: list[str] = []
	w = L.append

	w("// !$*UTF8*$!")
	w("{")
	w("\tarchiveVersion = 1;")
	w("\tclasses = {")
	w("\t};")
	w("\tobjectVersion = 56;")
	w("\tobjects = {")

	w("\n/* Begin PBXBuildFile section */")
	for n in sources + resources:
		kind = "Sources" if n.endswith(".swift") else "Resources"
		w(f"\t\t{build_files[n]} /* {n} in {kind} */ = {{isa = PBXBuildFile; fileRef = {file_refs[n]} /* {n} */; }};")
	w("/* End PBXBuildFile section */")

	w("\n/* Begin PBXFileReference section */")
	w(f'\t\t{product} /* {APP}.app */ = {{isa = PBXFileReference; explicitFileType = "wrapper.application"; '
	  f'includeInIndex = 0; path = "{APP}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};')
	for n in sources:
		w(f'\t\t{file_refs[n]} /* {n} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; '
		  f'path = "{n}"; sourceTree = "<group>"; }};')
	for n in resources:
		t = "folder.assetcatalog" if n.endswith(".xcassets") else "text.xml"
		w(f'\t\t{file_refs[n]} /* {n} */ = {{isa = PBXFileReference; lastKnownFileType = {t}; '
		  f'path = "{n}"; sourceTree = "<group>"; }};')
	w(f'\t\t{plist_ref} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; '
	  f'path = "Info.plist"; sourceTree = "<group>"; }};')
	w("/* End PBXFileReference section */")

	w("\n/* Begin PBXFrameworksBuildPhase section */")
	w(f"\t\t{frameworks_phase} /* Frameworks */ = {{")
	w("\t\t\tisa = PBXFrameworksBuildPhase;")
	w("\t\t\tbuildActionMask = 2147483647;")
	# SwiftUI and WebKit are auto-linked from their `import`s; no explicit entries needed.
	w("\t\t\tfiles = (")
	w("\t\t\t);")
	w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
	w("\t\t};")
	w("/* End PBXFrameworksBuildPhase section */")

	w("\n/* Begin PBXGroup section */")
	w(f"\t\t{main_group} = {{")
	w("\t\t\tisa = PBXGroup;")
	w("\t\t\tchildren = (")
	w(f"\t\t\t\t{app_group} /* {APP} */,")
	w(f"\t\t\t\t{products_group} /* Products */,")
	w("\t\t\t);")
	w("\t\t\tsourceTree = \"<group>\";")
	w("\t\t};")
	w(f"\t\t{app_group} /* {APP} */ = {{")
	w("\t\t\tisa = PBXGroup;")
	w("\t\t\tchildren = (")
	for n in sources + resources:
		w(f"\t\t\t\t{file_refs[n]} /* {n} */,")
	w(f"\t\t\t\t{plist_ref} /* Info.plist */,")
	w("\t\t\t);")
	w(f'\t\t\tpath = "{APP}";')
	w("\t\t\tsourceTree = \"<group>\";")
	w("\t\t};")
	w(f"\t\t{products_group} /* Products */ = {{")
	w("\t\t\tisa = PBXGroup;")
	w("\t\t\tchildren = (")
	w(f"\t\t\t\t{product} /* {APP}.app */,")
	w("\t\t\t);")
	w("\t\t\tname = Products;")
	w("\t\t\tsourceTree = \"<group>\";")
	w("\t\t};")
	w("/* End PBXGroup section */")

	w("\n/* Begin PBXNativeTarget section */")
	w(f"\t\t{target} /* {APP} */ = {{")
	w("\t\t\tisa = PBXNativeTarget;")
	w(f"\t\t\tbuildConfigurationList = {target_cfg_list} /* Build configuration list for PBXNativeTarget \"{APP}\" */;")
	w("\t\t\tbuildPhases = (")
	w(f"\t\t\t\t{sources_phase} /* Sources */,")
	w(f"\t\t\t\t{frameworks_phase} /* Frameworks */,")
	w(f"\t\t\t\t{resources_phase} /* Resources */,")
	w("\t\t\t);")
	w("\t\t\tbuildRules = (")
	w("\t\t\t);")
	w("\t\t\tdependencies = (")
	w("\t\t\t);")
	w(f'\t\t\tname = "{APP}";')
	w(f'\t\t\tproductName = "{APP}";')
	w(f"\t\t\tproductReference = {product} /* {APP}.app */;")
	w('\t\t\tproductType = "com.apple.product-type.application";')
	w("\t\t};")
	w("/* End PBXNativeTarget section */")

	w("\n/* Begin PBXProject section */")
	w(f"\t\t{proj} /* Project object */ = {{")
	w("\t\t\tisa = PBXProject;")
	w("\t\t\tattributes = {")
	w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
	w("\t\t\t\tLastSwiftUpdateCheck = 1500;")
	w("\t\t\t\tLastUpgradeCheck = 1500;")
	w("\t\t\t\tTargetAttributes = {")
	w(f"\t\t\t\t\t{target} = {{")
	w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
	w("\t\t\t\t\t};")
	w("\t\t\t\t};")
	w("\t\t\t};")
	w(f"\t\t\tbuildConfigurationList = {proj_cfg_list} /* Build configuration list for PBXProject \"{APP}\" */;")
	w('\t\t\tcompatibilityVersion = "Xcode 14.0";')
	w("\t\t\tdevelopmentRegion = en;")
	w("\t\t\thasScannedForEncodings = 0;")
	w("\t\t\tknownRegions = (")
	w("\t\t\t\ten,")
	w("\t\t\t\tBase,")
	w("\t\t\t);")
	w(f"\t\t\tmainGroup = {main_group};")
	w(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
	w('\t\t\tprojectDirPath = "";')
	w('\t\t\tprojectRoot = "";')
	w("\t\t\ttargets = (")
	w(f"\t\t\t\t{target} /* {APP} */,")
	w("\t\t\t);")
	w("\t\t};")
	w("/* End PBXProject section */")

	w("\n/* Begin PBXResourcesBuildPhase section */")
	w(f"\t\t{resources_phase} /* Resources */ = {{")
	w("\t\t\tisa = PBXResourcesBuildPhase;")
	w("\t\t\tbuildActionMask = 2147483647;")
	w("\t\t\tfiles = (")
	for n in resources:
		w(f"\t\t\t\t{build_files[n]} /* {n} in Resources */,")
	w("\t\t\t);")
	w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
	w("\t\t};")
	w("/* End PBXResourcesBuildPhase section */")

	w("\n/* Begin PBXSourcesBuildPhase section */")
	w(f"\t\t{sources_phase} /* Sources */ = {{")
	w("\t\t\tisa = PBXSourcesBuildPhase;")
	w("\t\t\tbuildActionMask = 2147483647;")
	w("\t\t\tfiles = (")
	for n in sources:
		w(f"\t\t\t\t{build_files[n]} /* {n} in Sources */,")
	w("\t\t\t);")
	w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
	w("\t\t};")
	w("/* End PBXSourcesBuildPhase section */")

	shared = [
		"ALWAYS_SEARCH_USER_PATHS = NO;",
		"CLANG_ENABLE_MODULES = YES;",
		"CLANG_ENABLE_OBJC_ARC = YES;",
		"COPY_PHASE_STRIP = NO;",
		"ENABLE_STRICT_OBJC_MSGSEND = YES;",
		f'IPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};',
		"SDKROOT = iphoneos;",
		"SWIFT_EMIT_LOC_STRINGS = YES;",
	]
	target_shared = [
		"ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
		"ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;",
		"CODE_SIGN_STYLE = Automatic;",
		f"CURRENT_PROJECT_VERSION = {CURRENT_PROJECT_VERSION};",
		'DEVELOPMENT_TEAM = "";',
		"ENABLE_PREVIEWS = YES;",
		"GENERATE_INFOPLIST_FILE = NO;",
		f'INFOPLIST_FILE = "{APP}/Info.plist";',
		'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");',
		f"MARKETING_VERSION = {MARKETING_VERSION};",
		f'PRODUCT_BUNDLE_IDENTIFIER = "{BUNDLE_ID}";',
		'PRODUCT_NAME = "$(TARGET_NAME)";',
		"SWIFT_EMIT_LOC_STRINGS = YES;",
		f"SWIFT_VERSION = {SWIFT_VERSION};",
		"TARGETED_DEVICE_FAMILY = 1;",
	]

	def config(ident: str, name: str, settings: list[str], comment: str) -> None:
		w(f"\t\t{ident} /* {comment} */ = {{")
		w("\t\t\tisa = XCBuildConfiguration;")
		w("\t\t\tbuildSettings = {")
		for s in settings:
			w(f"\t\t\t\t{s}")
		w("\t\t\t};")
		w(f"\t\t\tname = {name};")
		w("\t\t};")

	w("\n/* Begin XCBuildConfiguration section */")
	config(proj_debug, "Debug", shared + [
		"DEBUG_INFORMATION_FORMAT = dwarf;",
		"ENABLE_TESTABILITY = YES;",
		"GCC_OPTIMIZATION_LEVEL = 0;",
		'GCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");',
		"MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;",
		"ONLY_ACTIVE_ARCH = YES;",
		'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";',
		'SWIFT_OPTIMIZATION_LEVEL = "-Onone";',
	], "Debug")
	config(proj_release, "Release", shared + [
		'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";',
		"ENABLE_NS_ASSERTIONS = NO;",
		"MTL_ENABLE_DEBUG_INFO = NO;",
		"SWIFT_COMPILATION_MODE = wholemodule;",
		"VALIDATE_PRODUCT = YES;",
	], "Release")
	config(tgt_debug, "Debug", target_shared, "Debug")
	config(tgt_release, "Release", target_shared, "Release")
	w("/* End XCBuildConfiguration section */")

	w("\n/* Begin XCConfigurationList section */")
	for ident, dbg, rel, comment in (
		(proj_cfg_list, proj_debug, proj_release, f'Build configuration list for PBXProject "{APP}"'),
		(target_cfg_list, tgt_debug, tgt_release, f'Build configuration list for PBXNativeTarget "{APP}"'),
	):
		w(f"\t\t{ident} /* {comment} */ = {{")
		w("\t\t\tisa = XCConfigurationList;")
		w("\t\t\tbuildConfigurations = (")
		w(f"\t\t\t\t{dbg} /* Debug */,")
		w(f"\t\t\t\t{rel} /* Release */,")
		w("\t\t\t);")
		w("\t\t\tdefaultConfigurationIsVisible = 0;")
		w("\t\t\tdefaultConfigurationName = Release;")
		w("\t\t};")
	w("/* End XCConfigurationList section */")

	w("\t};")
	w(f"\trootObject = {proj} /* Project object */;")
	w("}")
	return "\n".join(L) + "\n", sources, resources


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target}"
               BuildableName = "{app}.app"
               BlueprintName = "{app}"
               ReferencedContainer = "container:{app}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "{app}.app"
            BlueprintName = "{app}"
            ReferencedContainer = "container:{app}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "{app}.app"
            BlueprintName = "{app}"
            ReferencedContainer = "container:{app}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def validate(text: str, sources: list[str], resources: list[str]) -> int:
	"""Check the object graph closes: every referenced id is defined, and nothing is orphaned."""
	bad = 0
	# Xcode writes the root group with no trailing comment, so a definition is "id =" with an
	# optional comment — not "id /* … */ =". Getting that wrong reports the root group as dangling.
	defined = set(re.findall(r"^\t\t([0-9A-F]{24})(?: /\*.*?\*/)? = \{", text, re.M))
	referenced = set(re.findall(r"\b([0-9A-F]{24})\b", text)) - defined
	# rootObject and the ids inside lists are referenced; all must be defined.
	dangling = sorted(referenced)
	if dangling:
		print(f"  FAIL  {len(dangling)} referenced id(s) are never defined: {dangling[:4]}")
		bad += 1
	else:
		print(f"  ok    every one of the {len(defined)} object ids referenced is defined")

	for name in sources:
		if f"{name} in Sources" not in text:
			print(f"  FAIL  {name} is not in the Sources build phase")
			bad += 1
	for name in resources:
		if f"{name} in Resources" not in text:
			print(f"  FAIL  {name} is not in the Resources build phase")
			bad += 1
	if not bad:
		print(f"  ok    all {len(sources)} source(s) compile and all {len(resources)} resource(s) are bundled")

	opens, closes = text.count("{"), text.count("}")
	if opens != closes:
		print(f"  FAIL  unbalanced braces: {opens} open, {closes} close")
		bad += 1
	else:
		print(f"  ok    braces balance ({opens})")

	for needed in ("rootObject = ", "isa = PBXProject;", "isa = PBXNativeTarget;", "// !$*UTF8*$!"):
		if needed not in text:
			print(f"  FAIL  missing {needed!r}")
			bad += 1
	return bad


def main() -> int:
	check = "--check" in sys.argv
	text, sources, resources = build_project()
	proj_dir = HERE / f"{APP}.xcodeproj"
	pbx = proj_dir / "project.pbxproj"

	if check:
		if not pbx.is_file():
			print(f"error: {pbx} does not exist — run without --check first")
			return 1
		text = pbx.read_text(encoding="utf-8")

	print(f"{'checking' if check else 'writing'} {pbx.relative_to(HERE.parent)}")
	print(f"  sources:   {', '.join(sources)}")
	print(f"  resources: {', '.join(resources) or '(none)'}")
	bad = validate(text, sources, resources)

	# The Info.plist must be parseable, or the build fails late and unhelpfully.
	try:
		plist = plistlib.loads((HERE / APP / "Info.plist").read_bytes())
		missing = [k for k in ("CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString",
		                       "CFBundleExecutable", "UILaunchScreen") if k not in plist]
		if missing:
			print(f"  FAIL  Info.plist is missing {missing}")
			bad += 1
		else:
			print(f"  ok    Info.plist parses and carries the required keys ({len(plist)} in total)")
	except Exception as e:                                  # noqa: BLE001
		print(f"  FAIL  Info.plist does not parse: {e}")
		bad += 1

	if bad:
		print(f"\n{bad} problem(s) — not writing." if not check else f"\n{bad} problem(s).")
		return 1

	if check:
		print("\nProject is internally consistent.")
		return 0

	proj_dir.mkdir(parents=True, exist_ok=True)
	pbx.write_text(text, encoding="utf-8")
	schemes = proj_dir / "xcshareddata" / "xcschemes"
	schemes.mkdir(parents=True, exist_ok=True)
	(schemes / f"{APP}.xcscheme").write_text(SCHEME.format(app=APP, target=oid("target")), encoding="utf-8")

	print("\nWrote the project and a shared scheme. Next:")
	print(f"  open ios/{APP}.xcodeproj")
	print("  select your team under Signing & Capabilities, then Run on a device")
	return 0


if __name__ == "__main__":
	sys.exit(main())
