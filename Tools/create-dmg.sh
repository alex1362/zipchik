#!/bin/zsh
set -euo pipefail

app_path=${1:?"Usage: create-dmg.sh <ZIP.app> <output.dmg>"}
output_dmg=${2:?"Usage: create-dmg.sh <ZIP.app> <output.dmg>"}
project_dir=${0:A:h:h}

[[ -d "$app_path" ]] || { echo "Application not found: $app_path" >&2; exit 1; }
[[ "$output_dmg" = /* ]] || output_dmg="$PWD/$output_dmg"

stage_dir=$(mktemp -d /private/tmp/zipchik-dmg.XXXXXX)
trap 'rm -rf "$stage_dir"' EXIT

ditto "$app_path" "$stage_dir/Zipchik.app"
ln -s /Applications "$stage_dir/Applications"
cp "$project_dir/Distribution/README.txt" "$stage_dir/README.txt"

mkdir -p "${output_dmg:h}"
hdiutil create -ov -volname "Zipchik" -srcfolder "$stage_dir" -format UDZO "$output_dmg"
echo "$output_dmg"
