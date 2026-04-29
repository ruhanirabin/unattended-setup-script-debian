#!/bin/bash
# =============================================================================
# Guardrail: require bash shell (scripts will not work in cmd.exe / PowerShell)
if [ -z "${BASH_VERSION:-}" ]; then
    echo "ERROR: This script requires bash. On Windows run as: bash $0 $*" >&2
    exit 1
fi
# =============================================================================
# Script: bump-version.sh
# Description: Bump the project version semantically.
#              Updates VERSION file, setup_auto_updates.sh fallback,
#              README.md badge, and any other version-dependent files.
# Usage: ./scripts/bump-version.sh <new-version>|patch|minor|major
# Examples:
#   ./scripts/bump-version.sh patch
#   ./scripts/bump-version.sh 3.2.0
# =============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${PROJECT_ROOT}/VERSION"

# Read current version
if [[ ! -f "$VERSION_FILE" ]]; then
    echo "ERROR: VERSION file not found at ${VERSION_FILE}" >&2
    exit 1
fi

CURRENT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
validate_semver() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: Invalid semver: ${version}" >&2
        exit 1
    fi
}

bump_semver() {
    local current="$1"
    local bump_type="$2"

    local major minor patch
    IFS='.' read -r major minor patch <<< "$current"

    case "$bump_type" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            echo "ERROR: Unknown bump type: ${bump_type}" >&2
            exit 1
            ;;
    esac

    echo "${major}.${minor}.${patch}"
}

# -----------------------------------------------------------------------------
# Determine new version
# -----------------------------------------------------------------------------
if [[ -z "${1:-}" ]]; then
    echo "Usage: $0 <new-version>|patch|minor|major" >&2
    echo "Examples:" >&2
    echo "  $0 patch     # Bump patch version (${CURRENT_VERSION} -> $(bump_semver "$CURRENT_VERSION" patch))" >&2
    echo "  $0 minor     # Bump minor version" >&2
    echo "  $0 major     # Bump major version" >&2
    echo "  $0 3.2.0     # Set specific version" >&2
    exit 1
fi

if [[ "$1" == "patch" || "$1" == "minor" || "$1" == "major" ]]; then
    NEW_VERSION="$(bump_semver "$CURRENT_VERSION" "$1")"
else
    NEW_VERSION="$1"
    validate_semver "$NEW_VERSION"
fi

if [[ "$NEW_VERSION" == "$CURRENT_VERSION" ]]; then
    echo "ERROR: New version (${NEW_VERSION}) is the same as current version" >&2
    exit 1
fi

echo "Bumping version: ${CURRENT_VERSION} -> ${NEW_VERSION}"

# -----------------------------------------------------------------------------
# Update files
# -----------------------------------------------------------------------------

# 1. VERSION file
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "Updated ${VERSION_FILE}"

# 2. setup_auto_updates.sh fallback version
SETUP_SCRIPT="${PROJECT_ROOT}/setup_auto_updates.sh"
if [[ -f "$SETUP_SCRIPT" ]]; then
    sed -i "s/^\( *\)VERSION=\"[0-9]\+\.[0-9]\+\.[0-9]\+\"$/\1VERSION=\"${NEW_VERSION}\"/" "$SETUP_SCRIPT"
    echo "Updated fallback version in ${SETUP_SCRIPT}"
else
    echo "WARN: ${SETUP_SCRIPT} not found" >&2
fi

# 3. README.md badge
README="${PROJECT_ROOT}/README.md"
if [[ -f "$README" ]]; then
    sed -i "s/version-[0-9]\+\.[0-9]\+\.[0-9]\+/version-${NEW_VERSION}/g" "$README"
    echo "Updated version badge in ${README}"
else
    echo "WARN: ${README} not found" >&2
fi

echo ""
echo "Version bumped to ${NEW_VERSION}"
echo "Run ./scripts/validate-version.sh to verify all files are consistent"
