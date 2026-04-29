#!/bin/bash
# =============================================================================
# Guardrail: require bash shell (scripts will not work in cmd.exe / PowerShell)
if [ -z "${BASH_VERSION:-}" ]; then
    echo "ERROR: This script requires bash. On Windows run as: bash $0 $*" >&2
    exit 1
fi
# =============================================================================
# Script: release.sh
# Description: Orchestrate the full release pipeline.
#   1) Bump VERSION file semantically
#   2) Run validation script confirming all dependent files reflect new version
#   3) Commit VERSION update
#   4) Tag release
#   5) Post-release verify VERSION consistency across all artifacts
# Usage: ./scripts/release.sh <new-version>|patch|minor|major
# =============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION_FILE="${PROJECT_ROOT}/VERSION"
BUMP_SCRIPT="${SCRIPT_DIR}/bump-version.sh"
VALIDATE_SCRIPT="${SCRIPT_DIR}/validate-version.sh"

error() {
    echo "ERROR: $*" >&2
    exit 1
}

info() {
    echo "INFO: $*"
}

warn() {
    echo "WARN: $*" >&2
}

# -----------------------------------------------------------------------------
# Prerequisites
# -----------------------------------------------------------------------------
command -v git >/dev/null 2>&1 || error "git is required"
[[ -f "$VERSION_FILE" ]] || error "VERSION file not found"
[[ -x "$BUMP_SCRIPT" ]] || error "bump-version.sh not found or not executable"
[[ -x "$VALIDATE_SCRIPT" ]] || error "validate-version.sh not found or not executable"

# Check for uncommitted changes
if ! git -C "$PROJECT_ROOT" diff-index --quiet HEAD --; then
    error "There are uncommitted changes. Please commit or stash them before releasing."
fi

CURRENT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
info "Current version: ${CURRENT_VERSION}"

# -----------------------------------------------------------------------------
# Parse argument
# -----------------------------------------------------------------------------
if [[ -z "${1:-}" ]]; then
    echo "Usage: $0 <new-version>|patch|minor|major" >&2
    echo "Examples:" >&2
    echo "  $0 patch     # Bump patch version" >&2
    echo "  $0 3.2.0     # Set specific version" >&2
    exit 1
fi

NEW_VERSION_ARG="$1"

# -----------------------------------------------------------------------------
# Step 1: Bump version
# -----------------------------------------------------------------------------
info "Step 1/5: Bumping version..."
if ! "$BUMP_SCRIPT" "$NEW_VERSION_ARG"; then
    error "Version bump failed"
fi

# Re-read version in case bump script computed it
NEW_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
info "Version is now: ${NEW_VERSION}"

# -----------------------------------------------------------------------------
# Step 2: Validate
# -----------------------------------------------------------------------------
info "Step 2/5: Validating version consistency..."
if ! "$VALIDATE_SCRIPT"; then
    error "Version validation failed. Please fix errors and try again."
fi

# -----------------------------------------------------------------------------
# Step 3: Commit
# -----------------------------------------------------------------------------
info "Step 3/5: Committing VERSION update..."
git -C "$PROJECT_ROOT" add -A
if ! git -C "$PROJECT_ROOT" commit -m "Bump version to ${NEW_VERSION}"; then
    error "Git commit failed"
fi
info "Committed with message: Bump version to ${NEW_VERSION}"

# -----------------------------------------------------------------------------
# Step 4: Tag release (release pipeline trigger)
# -----------------------------------------------------------------------------
info "Step 4/5: Tagging release..."
if ! git -C "$PROJECT_ROOT" tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}"; then
    error "Git tag failed"
fi
info "Created tag: v${NEW_VERSION}"
info "Release pipeline triggered (tag v${NEW_VERSION})"

# -----------------------------------------------------------------------------
# Step 5: Post-release validation
# -----------------------------------------------------------------------------
info "Step 5/5: Post-release validation..."
if ! "$VALIDATE_SCRIPT"; then
    warn "Post-release validation failed. Please review manually."
else
    info "Post-release validation passed"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  Release v${NEW_VERSION} is ready"
echo "============================================================"
echo ""
echo "Next steps:"
echo "  1. Push the commit and tag:"
echo "     git push && git push origin v${NEW_VERSION}"
echo "  2. Verify CI/CD release pipeline triggered correctly"
echo "  3. Verify release artifacts contain version ${NEW_VERSION}"
echo ""
