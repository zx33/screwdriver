#!/bin/zsh
# Sourced by build/test; all caches stay inside this checkout.
export CLANG_MODULE_CACHE_PATH="$task_root/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_root/.build/swift-module-cache"
task_spm_options=(--disable-sandbox --cache-path "$task_root/.build/cache" --config-path "$task_root/.build/config" --security-path "$task_root/.build/security" --manifest-cache local)

# Some upgraded Apple CLT installations retain a Swift 5.9 private interface
# beside a Swift 6 library. Use a local copy of its matching public interface.
task_compiler="$(xcrun --find swiftc)"
task_pm_dir="${task_compiler:A:h:h}/lib/swift/pm"
task_interfaces="$task_pm_dir/ManifestAPI/PackageDescription.swiftmodule"
task_private="$task_interfaces/arm64-apple-macos.private.swiftinterface"
task_public="$task_interfaces/arm64-apple-macos.swiftinterface"
if [[ -f "$task_private" && -f "$task_public" ]] &&
   /usr/bin/grep -q 'public enum SwiftVersion' "$task_private" &&
   /usr/bin/grep -q 'typealias SwiftVersion = PackageDescription.SwiftLanguageMode' "$task_public"; then
    task_local_pm="$task_root/.build/swiftpm-libs"
    mkdir -p "$task_local_pm"
    mkdir -p "$task_local_pm/ManifestAPI"
    cp -R -X "$task_pm_dir/ManifestAPI/" "$task_local_pm/ManifestAPI/"
    for task_arch in arm64 x86_64; do
        task_module="$task_local_pm/ManifestAPI/PackageDescription.swiftmodule/$task_arch-apple-macos"
        if [[ -f "$task_module.swiftinterface" ]]; then
            cp "$task_module.swiftinterface" "$task_module.private.swiftinterface"
        fi
    done
    export SWIFTPM_CUSTOM_LIBS_DIR="$task_local_pm"
fi

# The same partial CLT upgrade can leave two module maps for SwiftBridging.
# Hide only the obsolete map through a compiler VFS overlay, within this build.
task_legacy_map="${task_compiler:A:h:h}/include/swift/module.modulemap"
task_current_map="${task_compiler:A:h:h}/include/swift/bridging.modulemap"
if [[ -f "$task_legacy_map" && -f "$task_current_map" ]] &&
   /usr/bin/grep -q 'module SwiftBridging' "$task_legacy_map" &&
   /usr/bin/grep -q 'module SwiftBridging' "$task_current_map"; then
    task_overlay="$task_root/.build/toolchain-overlay.json"
    task_empty_map="$task_root/.build/empty.modulemap"
    mkdir -p "$task_root/.build"
    : > "$task_empty_map"
    printf '{"version":0,"roots":[{"type":"file","name":"%s","external-contents":"%s"}]}\n' "$task_legacy_map" "$task_empty_map" > "$task_overlay"
    task_spm_options+=(-Xswiftc -vfsoverlay -Xswiftc "$task_overlay")
fi
