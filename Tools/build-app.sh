#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
output_dir=${1:-"$project_dir/Build"}
app_path="$output_dir/ZIP.app"
binary_path="/opt/homebrew/opt/sevenzip/bin/7zz"
license_path="$project_dir/Resources/7-Zip-license.txt"
signing_identity="${ZIP_SIGNING_IDENTITY:--}"

[[ "$(uname -m)" == arm64* ]] || { echo "ZIP is built for Apple silicon only." >&2; exit 1; }
[[ -x "$binary_path" ]] || { echo "7zz is not installed: $binary_path" >&2; exit 1; }
[[ -f "$license_path" ]] || { echo "7-Zip license is not installed: $license_path" >&2; exit 1; }

swift build --package-path "$project_dir" --configuration release --scratch-path /private/tmp/zip-swift-release
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources/ThirdParty/7-Zip"
cp "$project_dir/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp -R "$project_dir/Resources/en.lproj" "$project_dir/Resources/ru.lproj" "$app_path/Contents/Resources/"
cp "/private/tmp/zip-swift-release/arm64-apple-macosx/release/ZIP" "$app_path/Contents/MacOS/ZIP"
cp "$binary_path" "$app_path/Contents/Resources/ThirdParty/7-Zip/7zz"
cp "$license_path" "$app_path/Contents/Resources/ThirdParty/7-Zip/license.txt"
chmod +x "$app_path/Contents/MacOS/ZIP" "$app_path/Contents/Resources/ThirdParty/7-Zip/7zz"
extension_path="$app_path/Contents/PlugIns/ZIPQuickLook.appex"
mkdir -p "$extension_path/Contents/MacOS" "$extension_path/Contents/Resources"
swiftc -parse-as-library -module-name ZIPQuickLook "$project_dir/Sources/ZIPQuickLook/PreviewViewController.swift" -framework AppKit -framework QuickLookUI -Xlinker -e -Xlinker _NSExtensionMain -o "$extension_path/Contents/MacOS/ZIPQuickLook"
cp "$project_dir/Resources/ZIPQuickLook/Info.plist" "$extension_path/Contents/Info.plist"
cp -R "$project_dir/Resources/en.lproj" "$project_dir/Resources/ru.lproj" "$extension_path/Contents/Resources/"
cp "$binary_path" "$extension_path/Contents/Resources/7zz"
cp "$license_path" "$extension_path/Contents/Resources/license.txt"
chmod +x "$extension_path/Contents/MacOS/ZIPQuickLook" "$extension_path/Contents/Resources/7zz"
codesign --force --sign "$signing_identity" --entitlements "$project_dir/Resources/ZIPQuickLook/7zz.entitlements" "$extension_path/Contents/Resources/7zz"
codesign --force --sign "$signing_identity" --entitlements "$project_dir/Resources/ZIPQuickLook/ZIPQuickLook.entitlements" "$extension_path"
codesign --force --sign "$signing_identity" "$app_path"
plutil -lint "$app_path/Contents/Info.plist"
echo "$app_path"
