#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output_dir="${1:-dist}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/mapannai-ipa.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcodegen generate
xcodebuild -project MapAnNai.xcodeproj -scheme MapAnNai \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$build_dir/build" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build
app="$build_dir/build/Build/Products/Release-iphoneos/MapAnNai.app"
python3 Scripts/verify-app-resources.py "$app"
python3 - "$app" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
with (app / 'Info.plist').open('rb') as f:
    info = plistlib.load(f)
key = info.get('AMapIOSKey', '').strip()
if not key or '$(' in key:
    raise SystemExit('Missing embedded AMap iOS key; configure Config/Local.xcconfig')
if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
    raise SystemExit('Expected a device build')
if (app / 'embedded.mobileprovision').exists() or (app / '_CodeSignature').exists():
    raise SystemExit('Expected unsigned app without provisioning profile')
print('Verified device platform, map configuration and unsigned app')
PY
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Info.plist")
if [[ -n "${RELEASE_VERSION:-}" && "$version" != "$RELEASE_VERSION" ]]; then
  echo 'Release tag and app version do not match' >&2
  exit 1
fi
mkdir -p "$build_dir/package/Payload"
cp -R "$app" "$build_dir/package/Payload/MapAnNai.app"
ipa="MapAnNai-${version}-unsigned.ipa"
(cd "$build_dir/package" && /usr/bin/zip -q -r "$output_dir/$ipa" Payload)
(cd "$output_dir" && shasum -a 256 "$ipa" > "$ipa.sha256")
unzip -tq "$output_dir/$ipa"
echo "Created $output_dir/$ipa"
