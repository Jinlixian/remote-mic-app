#!/usr/bin/env bash
# Build the locally runnable macOS SayAll.app from the current checkout.
# This entry point only compiles and verifies the app bundle: it does not
# launch, install, sign for distribution, or touch the single-instance lock.
# The public compatibility path needs no Developer ID and no private packages.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "$#" -ne 0 ]]; then
  printf 'usage: %s\n' "$0" >&2
  printf 'Builds dist/SayAll.app only; no arguments are accepted.\n' >&2
  exit 2
fi

VARIANT="$(uname -m)"
case "$VARIANT" in
  arm64) RELEASE_VARIANT=apple-silicon ;;
  x86_64) RELEASE_VARIANT=intel ;;
  *) printf 'Unsupported Mac architecture: %s\n' "$VARIANT" >&2; exit 1 ;;
esac

# Force the reproducible public packaging path. Clearing these variables keeps
# a shell that happens to export private-package paths from changing the build.
export RELEASE_VARIANT
export CONFIGURATION=release
export SAYALL_PRIVATE_PLATFORM_MODE=public
export REQUIRE_DEVELOPER_ID_SIGNING=0
export CODE_SIGN_IDENTITY=""
export SAYALL_BUILD_CHANNEL=""
export SAYALL_PRIVATE_SOURCE_ROOT=""
export REMOTE_MIC_SENTRY_DSN=""
export SAYALL_DIAGNOSTIC_PUBLIC_KEY_BASE64=""
export SAYALL_ENABLE_PRIVATE_SWIFTPM=""
export SAYALL_PRIVATE_PLATFORM_PACKAGE_PATH=""
export SAYALL_PRIVATE_ARTIFACT_PACKAGE_PATH=""
export SAYALL_MAC_REMOTE_PACKAGE_PATH=""
export SAYALL_SIRI_REMOTE_PACKAGE_PATH=""
export SAYALL_CHROMECAST_PACKAGE_PATH=""
export SAYALL_AI_PACKAGE_PATH=""
export SAYALL_COMBINATION_ACTIONS_PATH=""
export SAYALL_BUTTON_PROFILES_PACKAGE_PATH=""
export SAYALL_ENABLE_SIRI_REMOTE=""
export SAYALL_ENABLE_CHROMECAST=""
export SAYALL_ENABLE_BUTTON_PROFILES=""

# build-app.sh is verbose (Swift warnings and codesign progress). Keep the
# successful path quiet and print a concise summary; on failure, surface the
# full log so compilation errors are never hidden.
build_log="$(mktemp "${TMPDIR:-/tmp}/sayall-build-mac.XXXXXX")"
cleanup() { rm -f "$build_log"; }
trap cleanup EXIT
if ! "$ROOT/scripts/build-app.sh" >"$build_log" 2>&1; then
  cat "$build_log" >&2
  printf 'build-mac-app.sh: build-app.sh failed; see log above\n' >&2
  exit 1
fi

APP="$ROOT/dist/SayAll.app"
PLIST="$APP/Contents/Info.plist"
BINARY="$APP/Contents/MacOS/RemoteMic"

codesign --verify --deep --strict "$APP"

version="$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST")"
build="$(plutil -extract CFBundleVersion raw -o - "$PLIST")"
source_commit="$(plutil -extract SayAllSourceCommit raw -o - "$PLIST")"
arch="$(lipo -archs "$BINARY")"
signature="$(codesign -dv "$APP" 2>&1 | awk -F= '/^Signature=/{print $2; exit}')"

printf 'Built %s\n' "$APP"
printf '  version=%s build=%s arch=%s variant=%s\n' "$version" "$build" "$arch" "$RELEASE_VARIANT"
printf '  source_commit=%s\n' "$source_commit"
printf '  signature=%s (local ad-hoc; not notarized or distributable)\n' "$signature"
printf '  codesign --verify --deep --strict: passed\n'
