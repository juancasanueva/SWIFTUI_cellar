#!/usr/bin/env bash
#
# Build Cellar's Sparkle appcast for one published release.
#
# What this script is allowed to do: fetch the live feed, fetch and verify the
# pinned signing tool, sign one zip, merge one item, and write the result to an
# output directory. What it deliberately cannot do: publish, tag, retract, or
# select a repository. There is no `git` and no `gh` in it, and
# `AppcastScriptContractTests` asserts both — the release workflow's guarantee
# that it can only ever *create* a release is only worth something if the
# scripts it calls cannot quietly widen it.
#
# It never traces itself. `set -x` would echo the signing pipeline into the job
# log, and the signing pipeline is where the private key is.
#
# Environment contract:
#   VERSION              marketing version, without the leading v (1.2.3)
#   BUILD_NUMBER         the build number the release was archived with
#   GITHUB_REF_NAME      the tag; a hyphen in it means prerelease, and no item
#   ASSET_URL            the published zip's download URL
#   ZIP_PATH             the local zip that was published, to be signed
#   FEED_URL             the live feed, fetched so history is preserved
#   OUTPUT_DIR           where appcast.xml is written; never the repository tree
#   SPARKLE_PRIVATE_KEY  the EdDSA private key, read on **stdin only**
#
# Run it by hand exactly as CI runs it: every input is an environment variable
# and nothing is discovered from the checkout.

set -euo pipefail

# --- guard -------------------------------------------------------------------
# The same literal the workflow uses for `--prerelease`, restated here so a hand
# run behaves identically. A prerelease that reached the feed would be offered
# to every stable user; the version comparison alone would not stop that,
# because the feed is the thing being trusted.
case "$GITHUB_REF_NAME" in
	*-*)
		echo "prerelease $GITHUB_REF_NAME: no appcast item"
		exit 0
		;;
esac

VERSION="${VERSION:?VERSION is required}"
BUILD_NUMBER="${BUILD_NUMBER:?BUILD_NUMBER is required}"
ASSET_URL="${ASSET_URL:?ASSET_URL is required}"
ZIP_PATH="${ZIP_PATH:?ZIP_PATH is required}"
FEED_URL="${FEED_URL:?FEED_URL is required}"
OUTPUT_DIR="${OUTPUT_DIR:?OUTPUT_DIR is required}"

# The pinned signing tool. The version alone would not stop a tampered binary
# from signing the release with an attacker's key, and every installed copy
# would accept the result — the client only checks the signature against the key
# in its own bundle. The digest is what makes that unreachable, and the check
# runs before anything is signed.
SPARKLE_VERSION="2.9.6"
SPARKLE_TARBALL_SHA256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
SPARKLE_TARBALL_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

MINIMUM_SYSTEM_VERSION="15.0"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- fetch -------------------------------------------------------------------
# A 404 on the very first release is a designed state, not an error: there is no
# feed yet, so an empty channel is the correct starting point. Every later run
# merges into whatever is actually being served, which is what keeps items for
# versions a user skipped from disappearing.
echo "==> fetch $FEED_URL"
if ! curl -fsSL "$FEED_URL" -o "$WORK/current.xml"; then
	echo "    no live feed yet; starting an empty channel"
	: > "$WORK/current.xml"
fi
if [ ! -s "$WORK/current.xml" ]; then
	cat > "$WORK/current.xml" <<-XML
		<?xml version="1.0" encoding="UTF-8"?>
		<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
		    <channel>
		        <title>Cellar</title>
		        <description>Updates for Cellar</description>
		        <language>en</language>
		    </channel>
		</rss>
	XML
fi

# --- tool --------------------------------------------------------------------
echo "==> tool Sparkle $SPARKLE_VERSION"
curl -fsSL -o "$WORK/sparkle.tar.xz" "$SPARKLE_TARBALL_URL"
printf '%s  %s\n' "$SPARKLE_TARBALL_SHA256" "$WORK/sparkle.tar.xz" | shasum -a 256 -c -
tar -xJf "$WORK/sparkle.tar.xz" -C "$WORK"

# --- sign --------------------------------------------------------------------
# The key arrives on standard input and is never a file, never an argument, and
# never a redirection target. `--ed-key-file -` exists for exactly this: reading
# the key from a secret environment binding without writing it down anywhere.
# Under `set -u` an unset key aborts here rather than signing with nothing.
echo "==> sign $ZIP_PATH"
FRAGMENT="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$WORK/bin/sign_update" --ed-key-file - "$ZIP_PATH")"

# The signing tool's output shape is an input to this script, so it is checked
# rather than assumed. Both attributes are required by Cellar's offline appcast
# validator; a tool whose output shape changed would otherwise emit an item that
# every installed copy rejects, discovered only after the feed was published.
case "$FRAGMENT" in
	*'sparkle:edSignature="'*) ;;
	*) echo "the signing tool emitted no sparkle:edSignature" >&2; exit 1 ;;
esac
case "$FRAGMENT" in
	*'length="'*) ;;
	*) echo "the signing tool emitted no length=" >&2; exit 1 ;;
esac

# --- merge -------------------------------------------------------------------
# One item, prepended, with every prior item preserved in its existing order. A
# bad release is corrected by publishing a higher version, never by deleting a
# feed item: deleting one strands every copy that already saw it.
PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
# Written to a file rather than passed with `awk -v`: BSD awk rejects a newline
# inside a `-v` value outright, and the runner is macOS. Found by running this
# script for real rather than by reading it.
cat > "$WORK/item.xml" <<-XML
	        <item>
	            <title>Version ${VERSION}</title>
	            <pubDate>${PUB_DATE}</pubDate>
	            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
	            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
	            <sparkle:minimumSystemVersion>${MINIMUM_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
	            <enclosure url="${ASSET_URL}" ${FRAGMENT} type="application/octet-stream"/>
	        </item>
XML

mkdir -p "$OUTPUT_DIR"
# Inserted before the first existing item, or before the closing channel tag
# when there is none. Newest first, which is the order the offline validator
# requires and the order a merge must not disturb.
awk -v itemfile="$WORK/item.xml" '
	!inserted && ($0 ~ /<item>/ || $0 ~ /<\/channel>/) {
		while ((getline line < itemfile) > 0) { print line }
		close(itemfile)
		inserted = 1
	}
	{ print }
' "$WORK/current.xml" > "$OUTPUT_DIR/appcast.xml"

# --- emit --------------------------------------------------------------------
# Nothing is written into the repository tree, so there is no new stowaway
# surface, no `.gitignore` change, and nothing for a later step to commit.
echo "==> emit $OUTPUT_DIR/appcast.xml"
