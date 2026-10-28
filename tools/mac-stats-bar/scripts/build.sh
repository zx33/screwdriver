#!/bin/zsh
set -eu
task_root="${0:A:h:h}"
cd "$task_root"
task_flavor="${1:-preview}"
if (( $# > 1 )) || [[ "$task_flavor" != "stable" && "$task_flavor" != "preview" ]]; then
    printf 'Usage: scripts/build.sh [stable|preview]\n' >&2
    exit 2
fi
source "$task_root/scripts/environment.sh"
swift build -c release --product MacStatsBar "${task_spm_options[@]}" -j 4
task_bin="$(swift build -c release --show-bin-path "${task_spm_options[@]}")"
task_bundle="$task_root/dist/Mac Stats Bar.app"
if [[ "$task_flavor" == "preview" ]]; then
    task_bundle="$task_root/dist/Mac Stats Bar Preview.app"
fi
mkdir -p "$task_bundle/Contents/MacOS" "$task_bundle/Contents/Resources"
cp "$task_bin/MacStatsBar" "$task_bundle/Contents/MacOS/MacStatsBar"
cp "$task_root/Resources/Info.plist" "$task_bundle/Contents/Info.plist"
if [[ "$task_flavor" == "preview" ]]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.macstatsbar.preview' "$task_bundle/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName Mac Stats Bar Preview' "$task_bundle/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Mac Stats Bar Preview' "$task_bundle/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.2.1' "$task_bundle/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 3' "$task_bundle/Contents/Info.plist"
fi
task_signing_identity="${MAC_STATS_CODESIGN_IDENTITY:--}"
codesign --force --sign "$task_signing_identity" "$task_bundle"
codesign --verify --strict "$task_bundle"
printf 'Built: %s\n' "$task_bundle"
