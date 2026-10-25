#!/usr/bin/env python3
"""Generate a dependency-free iOS Xcode project from the Swift source folders."""
from pathlib import Path
from hashlib import sha1
import json

root = Path(__file__).resolve().parents[1]
objects = {}
def uid(name): return sha1(name.encode()).hexdigest()[:24].upper()
def ref(name): return uid(name)
def obj(name, value): objects[uid(name)] = value; return uid(name)
def q(value): return json.dumps(str(value))
def arr(values): return '(' + ', '.join(values) + ')'
def dictionary(values): return '{' + ' '.join(f'{k} = {v};' for k,v in values.items()) + '}'
def add(identity, isa, **values): return obj(identity, {'isa':isa, **values})

groups=[]
sources={}
for folder in ['LiftingCore','LiftingApp']:
    refs=[]; builds=[]
    for file in sorted((root/'Sources'/folder).glob('*.swift')):
        relative=file.relative_to(root)
        f=add(str(relative), 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=q(relative), sourceTree=q('<group>'))
        refs.append(f)
        builds.append(add('build:'+str(relative), 'PBXBuildFile', fileRef=f))
    groups.append(add('group:'+folder,'PBXGroup',children=arr(refs),name=q(folder),sourceTree=q('<group>')))
    sources[folder]=builds
testfile='Tests/LiftingCoreTests/TrainingTests.swift'
testref=add(testfile,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=q(testfile),sourceTree=q('<group>'))
groups.append(testref)
privacy=add('privacy','PBXFileReference',lastKnownFileType='text.xml',path=q('Resources/PrivacyInfo.xcprivacy'),sourceTree=q('<group>'))
assets=add('assets','PBXFileReference',lastKnownFileType='folder.assetcatalog',path=q('Resources/Assets.xcassets'),sourceTree=q('<group>'))
groups += [privacy,assets]
coreproduct=add('coreproduct','PBXFileReference',explicitFileType='wrapper.framework',path=q('LiftingCore.framework'),sourceTree='BUILT_PRODUCTS_DIR')
appproduct=add('appproduct','PBXFileReference',explicitFileType='wrapper.application',path=q('Setform.app'),sourceTree='BUILT_PRODUCTS_DIR')
testproduct=add('testproduct','PBXFileReference',explicitFileType='wrapper.cfbundle',path=q('LiftingCoreTests.xctest'),sourceTree='BUILT_PRODUCTS_DIR')
products=add('products','PBXGroup',children=arr([appproduct,coreproduct,testproduct]),name='Products',sourceTree=q('<group>'))
main=add('main','PBXGroup',children=arr(groups+[products]),sourceTree=q('<group>'))

common={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SUPPORTED_PLATFORMS':q('iphoneos iphonesimulator'),'TARGETED_DEVICE_FAMILY':q('1,2'),'CODE_SIGN_STYLE':'Automatic','MARKETING_VERSION':'1.0','CURRENT_PROJECT_VERSION':'11','GENERATE_INFOPLIST_FILE':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'YES','DEAD_CODE_STRIPPING':'YES','COPY_PHASE_STRIP':'YES'}
def configs(name,extras):
    ids=[]
    for mode in ['Debug','Release']:
        settings={**common,**extras}
        settings.update({'SWIFT_OPTIMIZATION_LEVEL':q('-Onone' if mode=='Debug' else '-Osize'),'DEBUG_INFORMATION_FORMAT':q('dwarf' if mode=='Debug' else 'dwarf-with-dsym')})
        if mode=='Debug': settings['ENABLE_TESTABILITY']='YES'; settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        else: settings['DEPLOYMENT_POSTPROCESSING']='YES'; settings['STRIP_INSTALLED_PRODUCT']='YES'
        ids.append(add(name+mode,'XCBuildConfiguration',buildSettings=dictionary(settings),name=mode))
    return add(name+'configs','XCConfigurationList',buildConfigurations=arr(ids),defaultConfigurationIsVisible='0',defaultConfigurationName='Release')

coreconfigs=configs('core',{'PRODUCT_BUNDLE_IDENTIFIER':'local.lifting.core','PRODUCT_NAME':q('$(TARGET_NAME)'),'DEFINES_MODULE':'YES','SKIP_INSTALL':'YES','DYLIB_INSTALL_NAME_BASE':q('@rpath')})
appconfigs=configs('app',{'PRODUCT_BUNDLE_IDENTIFIER':'local.lifting.app','PRODUCT_NAME':q('Setform'),'INFOPLIST_KEY_CFBundleDisplayName':'Setform','INFOPLIST_KEY_ITSAppUsesNonExemptEncryption':'NO','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','INFOPLIST_KEY_UISupportedInterfaceOrientations':q('UIInterfaceOrientationPortrait'),'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad':q('UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'),'LD_RUNPATH_SEARCH_PATHS':q('$(inherited) @executable_path/Frameworks'),'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CODE_SIGN_ENTITLEMENTS':q('Resources/Lifting.entitlements'),'INFOPLIST_KEY_NSHealthShareUsageDescription':q('Setform reads workouts, calories, and heart rate from Apple Health to add them to the matching workout in your history.'),'INFOPLIST_KEY_NSHealthUpdateUsageDescription':q('With Save Workouts to Apple Health on, Setform saves a strength workout only when nothing else recorded that time.')})
testconfigs=configs('test',{'PRODUCT_BUNDLE_IDENTIFIER':'local.lifting.tests','PRODUCT_NAME':q('$(TARGET_NAME)'),'LD_RUNPATH_SEARCH_PATHS':q('$(inherited) @loader_path/Frameworks @executable_path/Frameworks')})
projectconfigs=configs('project',{})
coresrc=add('coresrc','PBXSourcesBuildPhase',buildActionMask='2147483647',files=arr(sources['LiftingCore']),runOnlyForDeploymentPostprocessing='0')
appsrc=add('appsrc','PBXSourcesBuildPhase',buildActionMask='2147483647',files=arr(sources['LiftingApp']),runOnlyForDeploymentPostprocessing='0')
testsrc=add('testsrc','PBXSourcesBuildPhase',buildActionMask='2147483647',files=arr([add('testbuild','PBXBuildFile',fileRef=testref)]),runOnlyForDeploymentPostprocessing='0')
corelink=add('corelink','PBXBuildFile',fileRef=coreproduct)
testlink=add('testlink','PBXBuildFile',fileRef=coreproduct)
appframeworks=add('appframeworks','PBXFrameworksBuildPhase',buildActionMask='2147483647',files=arr([corelink]),runOnlyForDeploymentPostprocessing='0')
testframeworks=add('testframeworks','PBXFrameworksBuildPhase',buildActionMask='2147483647',files=arr([testlink]),runOnlyForDeploymentPostprocessing='0')
embed=add('embedbuild','PBXBuildFile',fileRef=coreproduct,settings=dictionary({'ATTRIBUTES':arr(['CodeSignOnCopy','RemoveHeadersOnCopy'])}))
embedphase=add('embed','PBXCopyFilesBuildPhase',buildActionMask='2147483647',dstPath=q(''),dstSubfolderSpec='10',files=arr([embed]),name=q('Embed Frameworks'),runOnlyForDeploymentPostprocessing='0')
resources=add('resources','PBXResourcesBuildPhase',buildActionMask='2147483647',files=arr([add('privacybuild','PBXBuildFile',fileRef=privacy),add('assetsbuild','PBXBuildFile',fileRef=assets)]),runOnlyForDeploymentPostprocessing='0')
core=add('coretarget','PBXNativeTarget',buildConfigurationList=coreconfigs,buildPhases=arr([coresrc]),buildRules='()',dependencies='()',name='LiftingCore',productName='LiftingCore',productReference=coreproduct,productType=q('com.apple.product-type.framework'))
proxy=add('coreproxy','PBXContainerItemProxy',containerPortal=ref('project'),proxyType='1',remoteGlobalIDString=core,remoteInfo='LiftingCore')
dependency=add('coredependency','PBXTargetDependency',target=core,targetProxy=proxy)
app=add('apptarget','PBXNativeTarget',buildConfigurationList=appconfigs,buildPhases=arr([appsrc,appframeworks,resources,embedphase]),buildRules='()',dependencies=arr([dependency]),name='Setform',productName='Setform',productReference=appproduct,productType=q('com.apple.product-type.application'))
test=add('testtarget','PBXNativeTarget',buildConfigurationList=testconfigs,buildPhases=arr([testsrc,testframeworks]),buildRules='()',dependencies=arr([dependency]),name='LiftingCoreTests',productName='LiftingCoreTests',productReference=testproduct,productType=q('com.apple.product-type.bundle.unit-test'))
add('project','PBXProject',attributes=dictionary({'LastUpgradeCheck':'1600','BuildIndependentTargetsInParallel':'YES'}),buildConfigurationList=projectconfigs,compatibilityVersion=q('Xcode 14.0'),developmentRegion='en',hasScannedForEncodings='0',knownRegions=arr(['en','Base']),mainGroup=main,productRefGroup=products,projectDirPath=q(''),projectRoot=q(''),targets=arr([app,core,test]))
project=root/'Lifting.xcodeproj'; project.mkdir(exist_ok=True)
contents='// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'
for key,value in objects.items(): contents += f'{key} = {dictionary(value)};\n'
contents += f'}}; rootObject = {ref("project")}; }}\n'
(project/'project.pbxproj').write_text(contents)
scheme=project/'xcshareddata/xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
def buildref(target,name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:Lifting.xcodeproj"/>'
appref=buildref(app,'Setform.app'); testref=buildref(test,'LiftingCoreTests.xctest')
(scheme/'Setform.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{appref}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO">{testref}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print(project)
