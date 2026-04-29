#!/bin/bash
# =============================================================================
# Guardrail: require bash shell (scripts will not work in cmd.exe / PowerShell)
if [ -z "${BASH_VERSION:-}" ]; then
    echo "ERROR: This script requires bash. On Windows run as: bash $0 $*" >&2
    exit 1
fi
# =============================================================================
# Script: validate-version.sh
# Description: Validate version consistency across all project artifacts.
#              Reads VERSION file and verifies all dependent files reflect it.
# Usage: ./scripts/validate-version.sh
# Exit: 0 if consistent, 1 if any mismatch found
# =============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${PROJECT_ROOT}/VERSION"

ERRORS=0

error() {
    echo "ERROR: $*" >&2
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo "WARN: $*" >&2
}

info() {
    echo "INFO: $*"
}

# -----------------------------------------------------------------------------
# Read expected version
# -----------------------------------------------------------------------------
if [[ ! -f "$VERSION_FILE" ]]; then
    error "VERSION file not found at ${VERSION_FILE}"
    exit 1
fi

EXPECTED_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
info "Expected version: ${EXPECTED_VERSION}"

# Validate semver format
if [[ ! "$EXPECTED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "VERSION file contains invalid semver: ${EXPECTED_VERSION}"
fi

# -----------------------------------------------------------------------------
# Check setup_auto_updates.sh
# -----------------------------------------------------------------------------
SETUP_SCRIPT="${PROJECT_ROOT}/setup_auto_updates.sh"
if [[ -f "$SETUP_SCRIPT" ]]; then
    # Check that it references the VERSION file
    if grep -q 'VERSION.*<.*VERSION.*' "$SETUP_SCRIPT" || grep -q 'VERSION file' "$SETUP_SCRIPT"; then
        info "setup_auto_updates.sh references VERSION file"
    else
        error "setup_auto_updates.sh does not reference VERSION file"
    fi

    # Check fallback version matches
    FALLBACK_VERSION="$(grep -oP 'VERSION="\K[0-9]+\.[0-9]+\.[0-9]+' "$SETUP_SCRIPT" | tail -1)"
    if [[ "$FALLBACK_VERSION" != "$EXPECTED_VERSION" ]]; then
        error "setup_auto_updates.sh fallback version (${FALLBACK_VERSION}) does not match VERSION (${EXPECTED_VERSION})"
    else
        info "setup_auto_updates.sh fallback version matches"
    fi
else
    error "setup_auto_updates.sh not found"
fi

# -----------------------------------------------------------------------------
# Check README.md badge
# -----------------------------------------------------------------------------
README="${PROJECT_ROOT}/README.md"
if [[ -f "$README" ]]; then
    BADGE_VERSION="$(grep -oP 'version-\K[0-9]+\.[0-9]+\.[0-9]+' "$README" | head -1)"
    if [[ "$BADGE_VERSION" == "$EXPECTED_VERSION" ]]; then
        info "README.md badge version matches"
    else
        error "README.md badge version (${BADGE_VERSION}) does not match VERSION (${EXPECTED_VERSION})"
    fi
else
    warn "README.md not found"
fi

# -----------------------------------------------------------------------------
# Check AGENTS.md
# -----------------------------------------------------------------------------
AGENTS="${PROJECT_ROOT}/AGENTS.md"
if [[ -f "$AGENTS" ]]; then
    if grep -q 'VERSION.*file.*single source of truth' "$AGENTS"; then
        info "AGENTS.md references VERSION file as SSOT"
    else
        error "AGENTS.md does not reference VERSION file as single source of truth"
    fi

    # Ensure no hardcoded version different from expected
    mapfile -t HARDCODED_VERSIONS < <(grep -oP '\b[0-9]+\.[0-9]+\.[0-9]+\b' "$AGENTS" || true)
    if [[ ${#HARDCODED_VERSIONS[@]} -gt 0 ]]; then
        for v in "${HARDCODED_VERSIONS[@]}"; do
            if [[ "$v" != "$EXPECTED_VERSION" ]]; then
                error "AGENTS.md contains hardcoded version ${v} that does not match VERSION"
            fi
        done
    fi
else
    warn "AGENTS.md not found"
fi

# -----------------------------------------------------------------------------
# Check CHANGELOG.md
# -----------------------------------------------------------------------------
CHANGELOG="${PROJECT_ROOT}/CHANGELOG.md"
if [[ -f "$CHANGELOG" ]]; then
    if grep -q "^## \[${EXPECTED_VERSION}\]" "$CHANGELOG"; then
        info "CHANGELOG.md contains section for ${EXPECTED_VERSION}"
    else
        warn "CHANGELOG.md does not contain section for ${EXPECTED_VERSION}"
    fi
else
    warn "CHANGELOG.md not found"
fi

# -----------------------------------------------------------------------------
# Check skills/release.md
# -----------------------------------------------------------------------------
RELEASE_SKILL="${PROJECT_ROOT}/skills/release.md"
if [[ -f "$RELEASE_SKILL" ]]; then
    if grep -q 'VERSION.*file' "$RELEASE_SKILL"; then
        info "skills/release.md references VERSION file"
    else
        error "skills/release.md does not reference VERSION file"
    fi
else
    warn "skills/release.md not found"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
if [[ "$ERRORS" -gt 0 ]]; then
    echo "VALIDATION FAILED: ${ERRORS} error(s) found" >&2
    exit 1
else
    echo "VALIDATION PASSED: All version references are consistent"
    exit 0
fi
