#!/bin/bash
#
# release.sh — archive, export, package, notarize, staple and verify a
# Developer ID build of Cellar.
#
# This is the build sequence, not a publishing path. It contains no version
# control and no release-management invocation of any kind, so it can neither
# select a repository nor publish, tag, or retract anything, whatever directory
# it is run from. Publication lives only in .github/workflows/release.yml.
# It also never creates, unlocks, or imports into a keychain: the workflow owns
# credentials, this file owns the build, and running these exact commands
# locally is what makes the local rehearsal a rehearsal rather than an
# approximation of one.
#
# Usage:
#   scripts/release.sh <archive|export|package|notarize|staple|verify|all>
#
# Environment:
#   VERSION            marketing version, e.g. 1.0.0                — all phases
#   BUILD_NUMBER       CURRENT_PROJECT_VERSION            — archive/export/verify
#   ASC_KEY_PATH       App Store Connect API key (.p8) path
#   ASC_KEY_ID         App Store Connect API key id
#   ASC_ISSUER_ID      App Store Connect issuer id
#                      — notarize, and archive/export when SIGNING_STYLE=automatic
#   SIGNING_STYLE      automatic (default) or manual
#   RELEASE_BUILD_DIR  output root, default "build" (excluded from the repository)

set -euo pipefail

readonly TEAM_ID="Z3S5JK8E38"
readonly SCHEME="cellar"
readonly PROJECT="cellar.xcodeproj"
readonly EXPORT_OPTIONS="scripts/ExportOptions.plist"

# The repository root is resolved from this file's own location, never from the
# working directory: a build that silently picks up whichever checkout happens
# to be current is a build nobody can reason about.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
SIGNING_STYLE="${SIGNING_STYLE:-automatic}"
BUILD="${RELEASE_BUILD_DIR:-build}"

ARCHIVE_PATH="$BUILD/$SCHEME.xcarchive"
EXPORT_DIR="$BUILD/export"
APP="$EXPORT_DIR/$SCHEME.app"
VERIFY_DIR="$BUILD/verify"
VERIFIED_APP="$VERIFY_DIR/$SCHEME.app"
ZIP=""
SIGN_FLAGS=()

usage() {
	cat >&2 <<'USAGE'
usage: scripts/release.sh <phase>

phases:
  archive    Build a Release archive stamped with VERSION / BUILD_NUMBER
  export     Export a Developer ID app, then gate its version and architecture
  package    ditto the exported app into Home-Cellar-<version>.zip
  notarize   Submit the archive and wait for Apple's verdict
  staple     Staple the ticket, then repackage so the asset carries it
  verify     Re-check every claim against the copy extracted from the zip
  all        Run the six phases above in order (the local rehearsal)
USAGE
}

fail() {
	echo "error: $*" >&2
	exit 1
}

require_env() {
	local name
	for name in "$@"; do
		if [ -z "${!name:-}" ]; then
			fail "$name must be set (see the header of scripts/release.sh)"
		fi
	done
}

expect_equal() {
	local actual="$1" expected="$2" what="$3"
	if [ "$actual" != "$expected" ]; then
		fail "$what is '$actual', expected '$expected'"
	fi
}

# DD-5: automatic signing needs the App Store Connect key; manual signing is the
# pre-authorized fallback and simply omits the flags.
configure_signing() {
	SIGN_FLAGS=()
	case "$SIGNING_STYLE" in
	automatic)
		require_env ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID
		SIGN_FLAGS=(
			-allowProvisioningUpdates
			-authenticationKeyPath "$ASC_KEY_PATH"
			-authenticationKeyID "$ASC_KEY_ID"
			-authenticationKeyIssuerID "$ASC_ISSUER_ID"
		)
		;;
	manual) ;;
	*) fail "SIGNING_STYLE must be 'automatic' or 'manual', not '$SIGNING_STYLE'" ;;
	esac
}

phase_archive() {
	require_env VERSION BUILD_NUMBER
	configure_signing
	echo "==> archive $VERSION ($BUILD_NUMBER)"

	rm -rf "$ARCHIVE_PATH"
	mkdir -p "$BUILD"
	xcodebuild archive \
		-project "$PROJECT" \
		-scheme "$SCHEME" \
		-configuration Release \
		-destination 'generic/platform=macOS' \
		-archivePath "$ARCHIVE_PATH" \
		ARCHS=arm64 \
		ONLY_ACTIVE_ARCH=NO \
		MARKETING_VERSION="$VERSION" \
		CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
		${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}
}

# DD-3, first of two gate passes: refuse to spend an Apple round trip on a
# mislabelled or wrongly built app. The second pass runs in `verify`, against
# the copy extracted from the published zip.
phase_export() {
	require_env VERSION
	configure_signing
	echo "==> export"

	rm -rf "$EXPORT_DIR"
	xcodebuild -exportArchive \
		-archivePath "$ARCHIVE_PATH" \
		-exportOptionsPlist "$EXPORT_OPTIONS" \
		-exportPath "$EXPORT_DIR" \
		${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}

	expect_equal \
		"$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")" \
		"$VERSION" "the exported CFBundleShortVersionString"
	expect_equal \
		"$(lipo -archs "$APP/Contents/MacOS/$SCHEME")" \
		"arm64" "the exported architecture"
}

phase_package() {
	require_env VERSION
	echo "==> package $ZIP"

	mkdir -p "$BUILD"
	ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"
}

phase_notarize() {
	require_env VERSION ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID
	echo "==> notarize"

	local response status submission
	response="$(xcrun notarytool submit "$ZIP" \
		--key "$ASC_KEY_PATH" \
		--key-id "$ASC_KEY_ID" \
		--issuer "$ASC_ISSUER_ID" \
		--wait --output-format json)" || response=""

	printf '%s\n' "$response"
	status="$(printf '%s' "$response" | plutil -extract status raw -o - - 2>/dev/null || true)"
	submission="$(printf '%s' "$response" | plutil -extract id raw -o - - 2>/dev/null || true)"

	if [ "$status" != "Accepted" ]; then
		# S17: the diagnostic log is surfaced rather than the run silently
		# retrying past the gate. Nothing is published either way.
		if [ -n "$submission" ]; then
			xcrun notarytool log "$submission" \
				--key "$ASC_KEY_PATH" \
				--key-id "$ASC_KEY_ID" \
				--issuer "$ASC_ISSUER_ID" >&2 || true
		fi
		fail "notarization did not succeed (status: ${status:-unknown})"
	fi
}

phase_staple() {
	require_env VERSION
	echo "==> staple"

	xcrun stapler staple "$APP"
	# `ditto` into an existing archive path adds to it rather than replacing it,
	# so the pre-notarization zip is deleted before the app is packaged again.
	# The published asset can then only be the stapled one — otherwise a
	# stranger's first launch would need network access to succeed (R8).
	rm -f "$ZIP"
	phase_package
}

# Every gate here runs on the copy extracted from the archive that is about to
# be published, which is what makes each one a statement about the artifact
# users download rather than about an intermediate build product.
phase_verify() {
	require_env VERSION BUILD_NUMBER
	echo "==> verify"

	rm -rf "$VERIFY_DIR"
	mkdir -p "$VERIFY_DIR"
	ditto -x -k "$ZIP" "$VERIFY_DIR"

	spctl -a -vvv -t install "$VERIFIED_APP"
	xcrun stapler validate "$VERIFIED_APP"
	codesign --verify --strict --verbose=2 "$VERIFIED_APP"

	local signing
	signing="$(codesign -dvvv "$VERIFIED_APP" 2>&1)"
	printf '%s\n' "$signing" >"$BUILD/codesign.txt"
	printf '%s\n' "$signing" | grep -q 'flags=0x10000(runtime)'
	printf '%s\n' "$signing" | grep -q 'Authority=Developer ID Application'
	printf '%s\n' "$signing" | grep -q "TeamIdentifier=$TEAM_ID"

	# The sandbox must be absent, and the check must be able to fail. `grep -qv`
	# succeeds as soon as any one line differs, so it never fails; and a bare
	# `! pipeline` is exempt from `set -e` by definition, so it cannot fail the
	# script either. An explicit branch is the only form of this gate that gates.
	if codesign -d --entitlements :- "$VERIFIED_APP" 2>&1 |
		grep -q 'com.apple.security.app-sandbox'; then
		fail "the delivered bundle carries an app-sandbox entitlement"
	fi

	expect_equal \
		"$(lipo -archs "$VERIFIED_APP/Contents/MacOS/$SCHEME")" \
		"arm64" "the delivered architecture"
	expect_equal \
		"$(plutil -extract CFBundleShortVersionString raw -o - "$VERIFIED_APP/Contents/Info.plist")" \
		"$VERSION" "the delivered CFBundleShortVersionString"
	expect_equal \
		"$(plutil -extract CFBundleVersion raw -o - "$VERIFIED_APP/Contents/Info.plist")" \
		"$BUILD_NUMBER" "the delivered CFBundleVersion"
	expect_equal \
		"$(plutil -extract CFBundleDisplayName raw -o - "$VERIFIED_APP/Contents/Info.plist")" \
		"Home-Cellar" "the delivered CFBundleDisplayName"

	# S23: nothing from scripts/ or .github/ may travel inside the bundle.
	# `cellar/` is a synchronized root group, so this is the gate that catches a
	# release file dropped into it by mistake.
	local stowaways
	stowaways="$(find "$VERIFIED_APP/Contents" \
		\( -name '*.yml' -o -name '*.yaml' -o -name '*.sh' -o -name 'ExportOptions*.plist' \) \
		-print)"
	if [ -n "$stowaways" ]; then
		printf 'error: release infrastructure shipped inside the bundle:\n%s\n' "$stowaways" >&2
		exit 1
	fi

	echo "==> verified $ZIP"
}

main() {
	local phase="${1:-}"

	case "$phase" in
	archive | export | package | notarize | staple | verify | all) ;;
	*)
		usage
		exit 1
		;;
	esac

	require_env VERSION
	ZIP="$BUILD/Home-Cellar-$VERSION.zip"

	case "$phase" in
	archive) phase_archive ;;
	export) phase_export ;;
	package) phase_package ;;
	notarize) phase_notarize ;;
	staple) phase_staple ;;
	verify) phase_verify ;;
	all)
		phase_archive
		phase_export
		phase_package
		phase_notarize
		phase_staple
		phase_verify
		;;
	esac
}

main "$@"
