#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
output_dir=${1:-"$project_dir/Build"}
app_path="$output_dir/ZIP.app"
derived_dir=/private/tmp/ZIPDerivedData
binary_path=/opt/homebrew/opt/sevenzip/bin/7zz
license_path="$project_dir/Resources/7-Zip-license.txt"
signing_identity="${ZIP_SIGNING_IDENTITY:--}"

[[ "$(uname -m)" == arm64* ]] || { echo "ZIP is built for Apple silicon only." >&2; exit 1; }
[[ -x "$binary_path" ]] || { echo "7zz is not installed: $binary_path" >&2; exit 1; }
lipo -archs "$binary_path" | grep -qw arm64 || { echo "7zz must contain arm64." >&2; exit 1; }
xcodegen generate --spec "$project_dir/project.yml" --project "$project_dir"
xcodebuild -project "$project_dir/ZIP.xcodeproj" -scheme ZIP -configuration Release -derivedDataPath "$derived_dir" CODE_SIGNING_ALLOWED=NO ARCHS=arm64 build

rm -rf "$app_path"
ditto "$derived_dir/Build/Products/Release/ZIP.app" "$app_path"
extension_path="$app_path/Contents/PlugIns/ZIPQuickLook.appex"
mkdir -p "$app_path/Contents/Resources/ThirdParty/7-Zip" "$extension_path/Contents/Resources"
cp "$binary_path" "$app_path/Contents/Resources/ThirdParty/7-Zip/7zz"
cp "$license_path" "$app_path/Contents/Resources/ThirdParty/7-Zip/license.txt"
chmod +x "$app_path/Contents/Resources/ThirdParty/7-Zip/7zz"

codesign --force --sign "$signing_identity" "$app_path/Contents/Resources/ThirdParty/7-Zip/7zz"
codesign --force --sign "$signing_identity" --entitlements "$project_dir/Resources/ZIPQuickLook/ZIPQuickLook.entitlements" "$extension_path"
codesign --force --sign "$signing_identity" "$app_path"
codesign --verify --deep --strict "$app_path"
echo "$app_path"
