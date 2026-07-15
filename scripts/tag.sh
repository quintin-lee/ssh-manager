#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

OLD_VERSION=$(cat VERSION)

if [[ $# -ge 1 ]]; then
    NEW_VERSION="$1"
else
    echo "Current version: $OLD_VERSION"
    read -r -p "New version: " NEW_VERSION
fi

# Validate semver format
if ! echo "$NEW_VERSION" | grep -qP '^\d+\.\d+\.\d+$'; then
    echo "Error: version must be in X.Y.Z format (e.g. 0.6.0)"
    exit 1
fi

if [[ "$OLD_VERSION" == "$NEW_VERSION" ]]; then
    echo "Error: new version is same as current ($OLD_VERSION)"
    exit 1
fi

echo "==> Bumping version: ${OLD_VERSION} → ${NEW_VERSION}"
echo ""

# -- Helper: portable sed in-place --
sed_i() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# -- 1. VERSION file --
echo "$NEW_VERSION" > VERSION
echo "  [1/4] VERSION  ................ ${NEW_VERSION}"

# -- 2. README.md --
# Global replace of OLD_VERSION with NEW_VERSION (all occurrences in README are version strings)
sed_i "s/${OLD_VERSION//./\\.}/${NEW_VERSION}/g" README.md
echo "  [2/4] README.md  .............. version badge & download links"

# -- 3. CHANGELOG.md --
TODAY=$(date +%Y-%m-%d)
sed_i "/^## \[Unreleased\]$/a\\\n## [${NEW_VERSION}] - ${TODAY}\n" CHANGELOG.md
echo "  [3/4] CHANGELOG.md  ........... added [${NEW_VERSION}] section"

# -- 4. Commit & Tag --
git add VERSION README.md CHANGELOG.md
git commit -m "chore: bump version to ${NEW_VERSION}"
git tag "v${NEW_VERSION}"

echo "  [4/4] git tag  ................ v${NEW_VERSION}"
echo ""
echo "Done! Tagged v${NEW_VERSION}"
echo "Run: git push --follow-tags"
