#!/usr/bin/env ruby
# frozen_string_literal: true

require "xcodeproj"
require "digest"
require "fileutils"
require "pathname"

class StowXcodeProject < Xcodeproj::Project
  def generate_available_uuid_list(count = 100)
    @stow_uuid_counter ||= 0
    new_uuids = (0..count).map do
      @stow_uuid_counter += 1
      Digest::SHA256.hexdigest("stow-xcodeproj-#{@stow_uuid_counter}")[0, 24].upcase
    end
    uniques = new_uuids - (@generated_uuids + uuids)
    @generated_uuids += uniques
    @available_uuids += uniques
  end
end

ROOT = File.expand_path("..", __dir__)
PROJECT_PATH = File.join(ROOT, "Stow.xcodeproj")
FileUtils.rm_rf(PROJECT_PATH)

project = StowXcodeProject.new(PROJECT_PATH)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2660"
project.root_object.attributes["LastUpgradeCheck"] = "2660"

sources_group = project.main_group.new_group("Sources", "Sources")
tests_group = project.main_group.new_group("Tests", "Tests")
config_group = project.main_group.new_group("Configuration", "Configuration")
resources_group = project.main_group.new_group("Resources", "Resources")

package_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package_ref.relative_path = "Packages/StowCore"
project.root_object.package_references << package_ref

def add_package(project, target, package_ref, product_name)
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.product_name = product_name
  dependency.package = package_ref
  target.package_product_dependencies << dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
end

def add_sources(group, target, root, relative_directories, source_root: "Sources")
  relative_directories.each do |relative_directory|
    absolute_directory = File.join(root, source_root, relative_directory)
    next unless Dir.exist?(absolute_directory)
    subgroup = group.groups.find { |candidate| candidate.path == relative_directory }
    subgroup ||= group.new_group(File.basename(relative_directory), relative_directory)
    Dir.glob(File.join(absolute_directory, "**", "*.swift")).sort.each do |path|
      relative = Pathname.new(path).relative_path_from(Pathname.new(File.join(root, source_root))).to_s
      file_path = relative.sub(%r{^#{Regexp.escape(relative_directory)}/?}, "")
      reference = subgroup.files.find { |candidate| candidate.path == file_path }
      reference ||= subgroup.new_file(file_path)
      target.add_file_references([reference])
    end
  end
end

def add_external_sources(project, target, root, relative_directory, group_name)
  absolute_directory = File.join(root, relative_directory)
  group = project.main_group.new_group(group_name, relative_directory)
  Dir.glob(File.join(absolute_directory, "**", "*.swift")).sort.each do |path|
    relative = Pathname.new(path).relative_path_from(Pathname.new(absolute_directory)).to_s
    target.add_file_references([group.new_file(relative)])
  end
end

def configure_target(target, platform:, deployment:, bundle_id:, info_plist:, entitlements: nil, module_name: nil)
  target.build_configurations.each do |configuration|
    settings = configuration.build_settings
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = bundle_id
    if info_plist
      settings["INFOPLIST_FILE"] = info_plist
      settings["GENERATE_INFOPLIST_FILE"] = "NO"
    else
      settings.delete("INFOPLIST_FILE")
      settings["GENERATE_INFOPLIST_FILE"] = "NO"
    end
    settings["SWIFT_VERSION"] = "6.0"
    settings["SWIFT_STRICT_CONCURRENCY"] = "complete"
    settings["CODE_SIGN_STYLE"] = "Automatic"
    settings["DEVELOPMENT_TEAM"] = ""
    settings["CURRENT_PROJECT_VERSION"] = "1"
    settings["MARKETING_VERSION"] = "0.1.1"
    settings["ENABLE_USER_SCRIPT_SANDBOXING"] = "YES"
    settings["ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS"] = "YES"
    settings["PRODUCT_MODULE_NAME"] = module_name if module_name
    settings["CODE_SIGN_ENTITLEMENTS"] = entitlements if entitlements
    if platform == :ios
      settings["IPHONEOS_DEPLOYMENT_TARGET"] = deployment
      settings["TARGETED_DEVICE_FAMILY"] = "1,2"
      settings["SUPPORTS_MACCATALYST"] = "NO"
    else
      settings["MACOSX_DEPLOYMENT_TARGET"] = deployment
      settings["CODE_SIGN_IDENTITY"] = "-" if configuration.name == "Debug"
    end
  end
end

ios_app = project.new_target(:application, "Stow-iOS", :ios, "17.0")
configure_target(ios_app, platform: :ios, deployment: "17.0", bundle_id: "dev.narumi.stow", info_plist: "Configuration/iOS-App-Info.plist", entitlements: "Configuration/Stow-iOS.entitlements", module_name: "StowApp")
add_sources(sources_group, ios_app, ROOT, ["StowApp/Shared", "StowApp/iOS"])
add_package(project, ios_app, package_ref, "StowCore")

mac_app = project.new_target(:application, "Stow-macOS", :osx, "14.0")
configure_target(mac_app, platform: :macos, deployment: "14.0", bundle_id: "dev.narumi.stow", info_plist: "Configuration/macOS-App-Info.plist", entitlements: "Configuration/Stow-macOS.entitlements", module_name: "StowApp")
add_sources(sources_group, mac_app, ROOT, ["StowApp/Shared", "StowApp/macOS"])
add_package(project, mac_app, package_ref, "StowCore")

cli = project.new_target(:command_line_tool, "StowCLI", :osx, "14.0")
configure_target(cli, platform: :macos, deployment: "14.0", bundle_id: "dev.narumi.stow.cli", info_plist: nil, entitlements: "Configuration/StowCLI.entitlements", module_name: "StowCLI")
cli.product_reference.name = "stow"
cli.product_reference.path = "stow"
cli.build_configurations.each do |configuration|
  configuration.build_settings["PRODUCT_NAME"] = "stow"
  configuration.build_settings["SKIP_INSTALL"] = "YES"
end
add_external_sources(project, cli, ROOT, "Packages/StowCore/Sources/StowCLI", "StowCLI")
add_package(project, cli, package_ref, "StowCore")
mac_app.add_dependency(cli)
cli_copy_phase = mac_app.new_copy_files_build_phase("Embed Stow CLI")
cli_copy_phase.symbol_dst_subfolder_spec = :wrapper
cli_copy_phase.dst_path = "Contents/Helpers"
cli_build_file = cli_copy_phase.add_file_reference(cli.product_reference, true)
cli_build_file.settings = { "ATTRIBUTES" => ["CodeSignOnCopy"] }

assets = resources_group.new_file("Assets.xcassets")
[ios_app, mac_app].each do |target|
  target.resources_build_phase.add_file_reference(assets, true)
  target.build_configurations.each { |configuration| configuration.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon" }
end

ios_share = project.new_target(:app_extension, "StowShare-iOS", :ios, "17.0")
configure_target(ios_share, platform: :ios, deployment: "17.0", bundle_id: "dev.narumi.stow.share.ios", info_plist: "Configuration/iOS-Share-Info.plist", entitlements: "Configuration/StowShare-iOS.entitlements", module_name: "StowShare")
add_sources(sources_group, ios_share, ROOT, ["StowShare/Shared", "StowShare/iOS"])
add_package(project, ios_share, package_ref, "StowCore")
ios_app.add_dependency(ios_share)
copy_phase = ios_app.new_copy_files_build_phase("Embed App Extensions")
copy_phase.symbol_dst_subfolder_spec = :plug_ins
copy_phase.add_file_reference(ios_share.product_reference, true)

mac_share = project.new_target(:app_extension, "StowShare-macOS", :osx, "14.0")
configure_target(mac_share, platform: :macos, deployment: "14.0", bundle_id: "dev.narumi.stow.share.macos", info_plist: "Configuration/macOS-Share-Info.plist", entitlements: "Configuration/StowShare-macOS.entitlements", module_name: "StowShare")
add_sources(sources_group, mac_share, ROOT, ["StowShare/Shared", "StowShare/macOS"])
add_package(project, mac_share, package_ref, "StowCore")
mac_app.add_dependency(mac_share)
copy_phase = mac_app.new_copy_files_build_phase("Embed App Extensions")
copy_phase.symbol_dst_subfolder_spec = :plug_ins
copy_phase.add_file_reference(mac_share.product_reference, true)

unit_tests = project.new_target(:unit_test_bundle, "StowAppTests", :osx, "14.0")
configure_target(unit_tests, platform: :macos, deployment: "14.0", bundle_id: "dev.narumi.stow.tests.unit", info_plist: "Configuration/Test-Info.plist", module_name: "StowAppTests")
add_sources(tests_group, unit_tests, ROOT, ["StowAppTests"], source_root: "Tests")
add_package(project, unit_tests, package_ref, "StowCore")
unit_tests.add_dependency(mac_app)
unit_tests.build_configurations.each do |configuration|
  configuration.build_settings["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/Stow-macOS.app/Contents/MacOS/Stow-macOS"
  configuration.build_settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
end

ui_tests = project.new_target(:ui_test_bundle, "StowUITests", :ios, "17.0")
configure_target(ui_tests, platform: :ios, deployment: "17.0", bundle_id: "dev.narumi.stow.tests.ui.ios", info_plist: "Configuration/Test-Info.plist", module_name: "StowUITests")
add_sources(tests_group, ui_tests, ROOT, ["StowUITests"], source_root: "Tests")
ui_tests.add_dependency(ios_app)
ui_tests.build_configurations.each { |c| c.build_settings["TEST_TARGET_NAME"] = "Stow-iOS" }

mac_ui_tests = project.new_target(:ui_test_bundle, "StowMacUITests", :osx, "14.0")
configure_target(mac_ui_tests, platform: :macos, deployment: "14.0", bundle_id: "dev.narumi.stow.tests.ui.macos", info_plist: "Configuration/Test-Info.plist", module_name: "StowMacUITests")
add_sources(tests_group, mac_ui_tests, ROOT, ["StowMacUITests"], source_root: "Tests")
mac_ui_tests.add_dependency(mac_app)
mac_ui_tests.build_configurations.each { |c| c.build_settings["TEST_TARGET_NAME"] = "Stow-macOS" }

project.build_configurations.each do |configuration|
  configuration.build_settings["SWIFT_VERSION"] = "6.0"
  configuration.build_settings["CLANG_ENABLE_MODULES"] = "YES"
  configuration.build_settings["SWIFT_STRICT_CONCURRENCY"] = "complete"
end

["iOS-App-Info.plist", "macOS-App-Info.plist", "iOS-Share-Info.plist", "macOS-Share-Info.plist", "Test-Info.plist",
 "Stow-iOS.entitlements", "Stow-macOS.entitlements", "StowCLI.entitlements", "StowShare-iOS.entitlements", "StowShare-macOS.entitlements"].each do |name|
  config_group.new_file(name)
end
privacy_manifest = config_group.new_file("PrivacyInfo.xcprivacy")
[ios_app, mac_app, ios_share, mac_share].each { |target| target.resources_build_phase.add_file_reference(privacy_manifest, true) }

project.save
project.recreate_user_schemes(visible: true)
shared_schemes = File.join(PROJECT_PATH, "xcshareddata", "xcschemes")
FileUtils.mkdir_p(shared_schemes)
Dir.glob(File.join(PROJECT_PATH, "xcuserdata", "**", "xcschemes", "*.xcscheme")).each do |scheme|
  FileUtils.cp(scheme, shared_schemes)
end
FileUtils.rm_rf(File.join(PROJECT_PATH, "xcuserdata"))
puts "Generated #{PROJECT_PATH}"
