developer_dir := env_var_or_default("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
derived_data := ".build/XcodeDerivedData"
macos_app := derived_data / "Build/Products/Debug/Stow-macOS.app"

default:
    @just --list

# Build and open the macOS app
macos:
    DEVELOPER_DIR="{{developer_dir}}" xcodebuild -quiet -project Stow.xcodeproj -scheme Stow-macOS -configuration Debug -derivedDataPath "{{derived_data}}" CODE_SIGN_ENTITLEMENTS='' CODE_SIGN_IDENTITY='-' build
    pkill -x Stow-macOS 2>/dev/null || true
    open "{{macos_app}}"

# Build the macOS app and install its CLI helper for the current user
install-cli:
    DEVELOPER_DIR="{{developer_dir}}" xcodebuild -quiet -project Stow.xcodeproj -scheme Stow-macOS -configuration Debug -derivedDataPath "{{derived_data}}" CODE_SIGN_ENTITLEMENTS='' CODE_SIGN_IDENTITY='-' build
    Scripts/install_cli.sh --app "{{macos_app}}"

# Remove the current user's Stow CLI symlink
uninstall-cli:
    Scripts/install_cli.sh --uninstall
