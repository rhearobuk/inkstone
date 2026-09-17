#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: bash Scripts/run-walkthrough.sh core|binder|import-review|full 'platform=...,id=...' [output-directory] [xcodebuild settings...]" >&2
    echo "Use a clean test library. This runs the real app and adds projects; it does not delete or reset your data." >&2
    exit 2
fi

mode=$1
destination=$2
shift 2
case "$mode" in
    core) test_filter=InkstoneWalkthroughTests/ReviewWalkthroughTests/testCoreAuthoringWalkthrough ;;
    binder) test_filter=InkstoneWalkthroughTests/ReviewWalkthroughTests/testBinderMoveWalkthrough ;;
    import-review) test_filter=InkstoneWalkthroughTests/ReviewWalkthroughTests/testImportAndAppleIntelligenceWalkthrough ;;
    full) test_filter=InkstoneWalkthroughTests/ReviewWalkthroughTests ;;
    *) echo "Mode must be core, binder, import-review, or full." >&2; exit 2 ;;
esac

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
output=${1:-"work/walkthrough-$(date +%Y%m%d-%H%M%S)"}
if [[ $# -gt 0 ]]; then shift; fi
if [[ -e "$output" ]]; then
    echo "Output already exists: $output. Choose a new directory; nothing was overwritten." >&2
    exit 2
fi
mkdir -p "$output"
output=$(cd "$output" && pwd)

printf 'Mode: %s\nDestination: %s\nConfiguration: Release\n' "$mode" "$destination" > "$output/run.txt"
git rev-parse HEAD >> "$output/run.txt"
git status --short >> "$output/run.txt"
xcodebuild -version >> "$output/run.txt"
echo "Start physical-device screen recording before the app launches."
echo "Import/review: choose the supplied Scrivener package when the file picker opens on iPad/Vision Pro."
echo "Results and screenshots: $output"

result=0
xcodebuild \
    -project AuthorApp.xcodeproj \
    -scheme "Inkstone Walkthrough" \
    -configuration Release \
    -destination "$destination" \
    -derivedDataPath "$output/DerivedData" \
    -resultBundlePath "$output/Walkthrough.xcresult" \
    -only-testing:"$test_filter" \
    -parallel-testing-enabled NO \
    -testLanguage en \
    -testRegion US \
    "$@" test 2>&1 | tee "$output/xcodebuild.log" || result=$?

if [[ -d "$output/Walkthrough.xcresult" ]]; then
    if ! xcrun xcresulttool export attachments \
        --path "$output/Walkthrough.xcresult" \
        --output-path "$output/attachments"; then
        echo "Could not export attachments. Open Walkthrough.xcresult in Xcode to inspect them." >&2
        if [[ $result -eq 0 ]]; then result=1; fi
    fi
fi
printf 'Exit status: %s\n' "$result" >> "$output/run.txt"
if [[ $result -ne 0 ]]; then
    echo "Walkthrough did not complete successfully. Do not label this run as passed." >&2
fi
exit "$result"
