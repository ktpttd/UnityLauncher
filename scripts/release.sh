#!/bin/sh
# Publishes a GitHub release: universal build, UnityLauncher.zip, tag v<version>.
#   scripts/release.sh 1.0.0
# install.sh downloads the zip from the latest release.
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/release.sh <version>}"
TAG="v$VERSION"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first."; exit 1; }
[ "$(git branch --show-current)" = main ] || { echo "Release from main."; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "Push main first."; exit 1; }
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then echo "$TAG already exists."; exit 1; fi

swift test
VERSION="$VERSION" UNIVERSAL=1 ./scripts/bundle.sh
rm -f build/UnityLauncher.zip
ditto -c -k --keepParent build/UnityLauncher.app build/UnityLauncher.zip

git tag -a "$TAG" -m "Unity Launcher $VERSION"
git push origin "$TAG"
gh release create "$TAG" build/UnityLauncher.zip --title "Unity Launcher $VERSION" --generate-notes
