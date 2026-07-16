#!/usr/bin/env bash
# ============================================================================
# [DEPRECATED] release.sh — Version bump and tag
#
# ⚠️  This script is superseded by scripts/tag.sh.
#     Please use tag.sh instead — it also updates README.md and CHANGELOG.md.
#
# Kept for reference. Remove once all team members/tooling have migrated.
# ============================================================================
set -euo pipefail

OLD_VERSION=$(cat VERSION)
echo "Current version: $OLD_VERSION"
read -r -p "New version: " NEW_VERSION

echo "$NEW_VERSION" > VERSION
git add VERSION
git commit -m "chore: bump version to $NEW_VERSION"
git tag "v$NEW_VERSION"
echo "Tagged v$NEW_VERSION. Run: git push --follow-tags"
