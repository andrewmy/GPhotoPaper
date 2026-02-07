derived_data := "/tmp/gphotopaper_deriveddata_release"
derived_data_debug := "/tmp/gphotopaper_deriveddata_debug"
derived_data_test := "/tmp/gphotopaper_deriveddata_test"
out_dir := "build/release-app"
out_dir_debug := "build/debug-app"
app_name := "GPhotoPaper.app"
app_binary := "GPhotoPaper"
scheme := "GPhotoPaper"
destination := "platform=macOS"
configuration := "Release"
configuration_debug := "Debug"
ui_test_target := "GPhotoPaperUITests"
entitlements := "GPhotoPaper/GPhotoPaper.entitlements"

build_archs := "arm64"
only_active_arch := "YES"

bundle_homebrew_prefix := "/opt/homebrew"
bundle_script := "bin/bundle-homebrew-dylibs.sh"

# Build a Release (non-Debug) macOS .app and copy it into a gitignored dir.
# Bundles any Homebrew dylibs the app links against (LibRaw + deps) and ad-hoc signs the result. (Not notarized.)
release-app:
  mkdir -p {{out_dir}}
  rm -rf {{out_dir}}/{{app_name}}
  xcodebuild -scheme {{scheme}} -destination '{{destination}}' -configuration {{configuration}} -derivedDataPath {{derived_data}} ARCHS={{build_archs}} ONLY_ACTIVE_ARCH={{only_active_arch}} build
  ditto {{derived_data}}/Build/Products/{{configuration}}/{{app_name}} {{out_dir}}/{{app_name}}
  {{bundle_script}} {{out_dir}}/{{app_name}} {{app_binary}} {{entitlements}} {{bundle_homebrew_prefix}}
  @echo "Built {{out_dir}}/{{app_name}}"

# Build a Debug macOS .app and copy it into a gitignored dir.
debug-app:
  mkdir -p {{out_dir_debug}}
  rm -rf {{out_dir_debug}}/{{app_name}}
  xcodebuild -scheme {{scheme}} -destination '{{destination}}' -configuration {{configuration_debug}} -derivedDataPath {{derived_data_debug}} ARCHS={{build_archs}} ONLY_ACTIVE_ARCH={{only_active_arch}} build
  ditto {{derived_data_debug}}/Build/Products/{{configuration_debug}}/{{app_name}} {{out_dir_debug}}/{{app_name}}
  {{bundle_script}} {{out_dir_debug}}/{{app_name}} {{app_binary}} {{entitlements}} {{bundle_homebrew_prefix}}
  @echo "Built {{out_dir_debug}}/{{app_name}}"

# Run unit tests (skips UI tests, which require extra app bootstrapping).
test:
  xcodebuild -scheme {{scheme}} -destination '{{destination}}' -derivedDataPath {{derived_data_test}} CODE_SIGNING_ALLOWED=NO test -skip-testing:{{ui_test_target}}
