#!/usr/bin/env bash
# ============================================================================
# tag.sh — Bump version and create git tag
#
# Usage:
#   ./scripts/tag.sh              # Interactive: prompts for new version
#   ./scripts/tag.sh 0.6.0        # Non-interactive: bump to specified version
#
# Workflow:
#   1. Update VERSION file        — write new version string
#   2. Update README.md           — replace version badge + download links
#   3. Update CHANGELOG.md        — insert [new version] section after [Unreleased]
#   4. Commit & tag               — git commit + git tag v<version>
#
# After running, push with:
#   git push --follow-tags
#
# CI (GitHub Actions) automatically builds all package formats and creates
# a GitHub Release on any v* tag push. See .github/workflows/release.yml.
# ============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

OLD_VERSION=$(cat VERSION)

# Accept version from argument or prompt
if [[ $# -ge 1 ]]; then
    NEW_VERSION="$1"
else
    echo "Current version: $OLD_VERSION"
    read -r -p "New version: " NEW_VERSION
fi

# Validate semver format (X.Y.Z)
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

# ---------------------------------------------------------------------------
# Step 1: Write new version to single source-of-truth file
# ---------------------------------------------------------------------------
echo "$NEW_VERSION" > VERSION
echo "  [1/4] VERSION  ................ ${NEW_VERSION}"

# ---------------------------------------------------------------------------
# Step 2: Replace version strings in README (badge + download links)
# ---------------------------------------------------------------------------
# All occurrences in README are version strings (badge, download links).
sed_i "s/${OLD_VERSION//./\\.}/${NEW_VERSION}/g" README.md
echo "  [2/4] README.md  .............. version badge & download links"

# ---------------------------------------------------------------------------
# Step 3: Insert version section in changelog
#   Before: ## [Unreleased] \n ### Added ...  After: ## [Unreleased] \n ## [X.Y.Z] - date \n ### Added ...
# ---------------------------------------------------------------------------
TODAY=$(date +%Y-%m-%d)
sed_i "/^## \[Unreleased\]$/a\\\n## [${NEW_VERSION}] - ${TODAY}\n" CHANGELOG.md
echo "  [3/4] CHANGELOG.md  ........... added [${NEW_VERSION}] section"

# ---------------------------------------------------------------------------
# Step 4: Commit changes and create annotated tag
# ---------------------------------------------------------------------------
git add VERSION README.md CHANGELOG.md
git commit -m "chore: bump version to ${NEW_VERSION}"
git tag "v${NEW_VERSION}"

echo "  [4/4] git tag  ................ v${NEW_VERSION}"
echo ""
echo "Done! Tagged v${NEW_VERSION}"
echo "Run: git push --follow-tags"
