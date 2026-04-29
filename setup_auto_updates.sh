#!/bin/bash
# =============================================================================
# Script: Automatic Security Updates Setup
# Version: see VERSION file (fallback embedded for standalone use)
# Author: Ruhani Rabin
# License: MIT
# Description: Sets up automatic security updates using unattended-upgrades
#              on Ubuntu 24.04+ and Debian 13+.
#
# Supported distributions:
#   Ubuntu: 24.04 (Noble), 24.10 (Oracular), 25.04 (Plucky), 25.10 (Questing),
#           26.04 (Resolute), 26.10
#   Debian: 13 (Trixie), 14 (Forky), Sid (Unstable)
#
# Automation-friendly: supports --yes, --dry-run, --quiet for Ansible/CI/CD.
#
# WARNING: This script will back up and may overwrite existing configuration
#          files. Backups are created at /etc/apt/apt.conf.d/<file>.bak.<timestamp>
# =============================================================================

set -o pipefail

# =============================================================================
# SINGLE SOURCE-OF-TRUTH VERSION
# =============================================================================
# Read from VERSION file when running from the repository; fallback to embedded
# version for standalone downloads (curl | bash).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/VERSION" ]]; then
    VERSION="$(tr -d '[:space:]' < "${SCRIPT_DIR}/VERSION")"
else
    VERSION="3.2.0"
fi

# =============================================================================
# GLOBALS
# =============================================================================
LOG_FILE="/var/log/unattended-setup.log"
VERBOSE=0
DRY_RUN=0
NON_INTERACTIVE=0
QUIET=0
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
BACKUP_SUFFIX="bak.${TIMESTAMP}"
HAS_SYSTEMD=0
CHANGES_MADE=0
SCRIPT_NAME="$(basename "$0")"
LOCK_FILE="/var/run/${SCRIPT_NAME}.lock"

# Supported version maps
declare -A SUPPORTED_UBUNTU=(
    ["24.04"]="noble"
    ["24.10"]="oracular"
    ["25.04"]="plucky"
    ["25.10"]="questing"
    ["26.04"]="resolute"
    ["26.10"]=""
)

declare -A SUPPORTED_DEBIAN=(
    ["13"]="trixie"
    ["14"]="forky"
    ["unstable"]="sid"
    [""]=""
)

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================
log_init() {
    if [[ "$DRY_RUN" -eq 0 ]]; then
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
        : > "$LOG_FILE" 2>/dev/null || LOG_FILE="/dev/null"
    fi
}

log_write() {
    local level="$1"
    shift
    local message="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${ts}] [${level}] ${message}" >> "$LOG_FILE" 2>/dev/null
}

log_info() {
    if [[ "$QUIET" -eq 0 ]]; then
        echo "INFO: $*"
    fi
    log_write "INFO" "$*"
}

log_warn() {
    if [[ "$QUIET" -eq 0 ]]; then
        echo "WARNING: $*" >&2
    fi
    log_write "WARN" "$*"
}

log_error() {
    if [[ "$QUIET" -eq 0 ]]; then
        echo "ERROR: $*" >&2
    fi
    log_write "ERROR" "$*"
}

log_debug() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        echo "DEBUG: $*"
    fi
    log_write "DEBUG" "$*"
}

# =============================================================================
# ERROR HANDLING
# =============================================================================
err_handler() {
    local exit_code=$?
    local line_number="${BASH_LINENO[0]}"
    log_error "Script failed at line ${line_number} with exit code ${exit_code}"
    log_error "Check ${LOG_FILE} for details"
    if [[ "$QUIET" -eq 0 ]]; then
        echo ""
        echo "ERROR: An error occurred during setup (line ${line_number}, exit code ${exit_code})."
        echo "       Review the log at ${LOG_FILE} for troubleshooting."
        echo ""
    fi
    exit "$exit_code"
}

trap err_handler ERR

cleanup() {
    local exit_code=$?
    rm -f "$LOCK_FILE" 2>/dev/null || true
    if [[ $exit_code -ne 0 ]]; then
        log_warn "Script exited with non-zero status: ${exit_code}"
        if [[ "$QUIET" -eq 0 ]]; then
            echo ""
            log_info "If the service was partially configured, you can check its status with:"
            log_info "  systemctl status unattended-upgrades"
            log_info "  journalctl -u unattended-upgrades"
        fi
    fi
}

trap cleanup EXIT

# =============================================================================
# USAGE / HELP
# =============================================================================
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Set up automatic security updates using unattended-upgrades.

Options:
  -y, --yes          Skip all confirmation prompts (non-interactive mode)
  -n, --dry-run      Validate environment and configuration without making changes
  -q, --quiet        Minimal output (errors and summary only)
  -v, --verbose      Enable verbose/debug output
  -l, --log-file     Specify custom log file path (default: ${LOG_FILE})
  -h, --help         Show this help message and exit

Automation Examples:
  $0 --yes                      # Ansible / non-interactive
  $0 --yes --quiet              # CI/CD with minimal output
  $0 --dry-run                  # Validate only
  $0 --yes --verbose            # Debug automation issues

Supported Distributions:
  Ubuntu: 24.04, 24.10, 25.04, 25.10, 26.04, 26.10
  Debian: 13 (Trixie), 14 (Forky), Sid (Unstable)

Version: ${VERSION}
EOF
}

# =============================================================================
# PARSE CLI ARGUMENTS
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
                NON_INTERACTIVE=1
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=1
                shift
                ;;
            -q|--quiet)
                QUIET=1
                NON_INTERACTIVE=1
                shift
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -l|--log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# LOCK FILE (prevent concurrent runs)
# =============================================================================
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid="$(cat "$LOCK_FILE" 2>/dev/null)"
        if kill -0 "$pid" 2>/dev/null; then
            log_error "Another instance is already running (PID: ${pid})"
            exit 1
        fi
        log_warn "Stale lock file found, removing"
        rm -f "$LOCK_FILE"
    fi
    echo "$$" > "$LOCK_FILE"
}

# =============================================================================
# BANNER
# =============================================================================
show_banner() {
    if [[ "$QUIET" -eq 1 ]]; then
        return
    fi
    echo "============================================================"
    echo "  Automatic Security Updates Setup"
    echo "  Version: ${VERSION}"
    echo "  Author: Ruhani Rabin"
    echo "  License: MIT"
    echo "============================================================"
    echo ""
}

# =============================================================================
# ROOT CHECK
# =============================================================================
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "This script must be run as root (use sudo or run as root)"
        exit 1
    fi
    log_debug "Running as root (uid=$(id -u))"
}

# =============================================================================
# SYSTEMD DETECTION
# =============================================================================
detect_systemd() {
    if command -v systemctl >/dev/null 2>&1 && systemctl >/dev/null 2>&1; then
        HAS_SYSTEMD=1
        log_debug "systemd detected"
    else
        HAS_SYSTEMD=0
        log_warn "systemd not detected — skipping service enable/start"
        if [[ "$QUIET" -eq 0 ]]; then
            echo "  Note: systemd not available. Configuration files will still be written."
            echo "        You may need to start the service manually or use cron."
        fi
    fi
}

# =============================================================================
# APT LOCK WAIT
# =============================================================================
wait_for_apt_lock() {
    local lock_files=("/var/lib/dpkg/lock" "/var/lib/dpkg/lock-frontend" "/var/lib/apt/lists/lock")
    local waited=0
    local max_wait=300

    log_debug "Checking for apt locks..."

    while true; do
        local locked=0
        for lf in "${lock_files[@]}"; do
            if fuser "$lf" >/dev/null 2>&1; then
                locked=1
                break
            fi
        done

        if [[ "$locked" -eq 0 ]]; then
            log_debug "No apt locks detected"
            return 0
        fi

        if [[ "$waited" -ge "$max_wait" ]]; then
            log_error "Apt lock held for more than ${max_wait}s. Another package manager may be running."
            exit 1
        fi

        if [[ "$QUIET" -eq 0 ]] && [[ "$waited" -eq 0 ]]; then
            echo "  Waiting for apt lock to be released..."
        fi

        sleep 5
        waited=$((waited + 5))
    done
}

# =============================================================================
# DISTRIBUTION DETECTION
# =============================================================================
detect_distribution() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Unable to detect distribution: /etc/os-release not found"
        exit 1
    fi

    # shellcheck source=/dev/null
    . /etc/os-release

    DISTRO_ID="${ID}"
    DISTRO_VERSION_ID="${VERSION_ID:-}"
    DISTRO_CODENAME="${VERSION_CODENAME:-}"
    DISTRO_NAME="${NAME:-Unknown}"

    # Explicitly reject desktop-oriented distributions
    local id_like="${ID_LIKE:-}"
    if [[ "$DISTRO_ID" == "linuxmint" ]] || [[ "$id_like" == *"linuxmint"* ]]; then
        log_error "Linux Mint and other desktop-oriented distributions are not supported."
        log_error "This script is designed for server environments (Ubuntu 24.04+ / Debian 13+)."
        exit 1
    fi

    log_info "Detected: ${DISTRO_NAME} ${DISTRO_VERSION_ID} (${DISTRO_CODENAME})"
    log_debug "ID=${DISTRO_ID}, VERSION_ID=${DISTRO_VERSION_ID}, CODENAME=${DISTRO_CODENAME}"

    validate_distribution
}

validate_distribution() {
    case "$DISTRO_ID" in
        ubuntu)
            if [[ -z "$DISTRO_CODENAME" ]] && [[ -n "${UBUNTU_CODENAME:-}" ]]; then
                DISTRO_CODENAME="$UBUNTU_CODENAME"
            fi

            if [[ -z "${SUPPORTED_UBUNTU[$DISTRO_VERSION_ID]+x}" ]]; then
                log_error "Unsupported Ubuntu version: ${DISTRO_VERSION_ID}"
                log_error "Supported versions: ${!SUPPORTED_UBUNTU[*]}"
                exit 1
            fi
            log_info "Ubuntu ${DISTRO_VERSION_ID} is supported"
            ;;
        debian)
            if [[ "$DISTRO_VERSION_ID" == "unstable" ]] || [[ "$DISTRO_CODENAME" == "sid" ]]; then
                DISTRO_VERSION_ID="unstable"
                log_info "Debian Sid (unstable) is supported"
            elif [[ -z "${SUPPORTED_DEBIAN[$DISTRO_VERSION_ID]+x}" ]]; then
                log_error "Unsupported Debian version: ${DISTRO_VERSION_ID}"
                log_error "Supported versions: 13, 14, unstable (sid)"
                exit 1
            else
                log_info "Debian ${DISTRO_VERSION_ID} is supported"
            fi
            ;;
        *)
            log_error "Unsupported distribution: ${DISTRO_ID}"
            log_error "This script supports Ubuntu 24.04+ and Debian 13+"
            exit 1
            ;;
    esac
}

# =============================================================================
# CONFIRMATION PROMPTS
# =============================================================================
check_existing_configuration() {
    if [[ "$HAS_SYSTEMD" -eq 1 ]] && systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
        log_warn "Unattended-upgrades service is already active"
        if [[ "$NON_INTERACTIVE" -eq 0 ]]; then
            echo ""
            echo "The unattended-upgrades service is already running."
            echo "Continuing will reconfigure and potentially overwrite existing settings."
            echo ""
            read -rp "Do you want to continue? (y/N): " response
            case "$response" in
                [yY][eE][sS]|[yY])
                    log_info "User chose to continue with reconfiguration"
                    ;;
                *)
                    log_info "Setup cancelled by user"
                    exit 0
                    ;;
            esac
        else
            log_info "Non-interactive mode: continuing despite active service"
        fi
    else
        log_info "No active unattended-upgrades service detected"
    fi
}

prompt_confirmation() {
    if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
        log_info "Non-interactive mode: proceeding without prompt"
        return
    fi

    echo ""
    echo "This script will:"
    echo "  - Install unattended-upgrades package"
    echo "  - Configure automatic security updates"
    echo "  - Back up and potentially overwrite existing APT configuration"
    echo ""
    read -rp "Do you want to continue? (y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY])
            log_info "User confirmed setup"
            ;;
        *)
            log_info "Setup cancelled by user"
            exit 0
            ;;
    esac
}

# =============================================================================
# IDEMPOTENCY HELPERS
# =============================================================================
mark_changed() {
    CHANGES_MADE=1
    log_debug "Change marked: $*"
}

files_differ() {
    local new_content="$1"
    local file="$2"
    if [[ ! -f "$file" ]]; then
        return 0
    fi
    if printf '%s\n' "$new_content" | diff -q - "$file" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# =============================================================================
# BACKUP EXISTING CONFIGURATION
# =============================================================================
backup_config() {
    local file="$1"
    local target="/etc/apt/apt.conf.d/${file}"

    if [[ -f "$target" ]]; then
        local backup="${target}.${BACKUP_SUFFIX}"
        if ! cp -p "$target" "$backup"; then
            log_error "Failed to backup ${target}"
            exit 1
        fi
        log_info "Backed up ${target} -> ${backup}"
        if [[ "$QUIET" -eq 0 ]]; then
            echo "  Backed up: ${file} -> ${file}.${BACKUP_SUFFIX}"
        fi
    else
        log_debug "No existing config to back up: ${target}"
    fi
}

# =============================================================================
# INSTALL PACKAGES
# =============================================================================
install_packages() {
    log_info "Installing required packages..."
    if [[ "$QUIET" -eq 0 ]]; then
        echo ""
        echo "--- Installing packages ---"
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[DRY RUN] Would run: apt-get update"
        log_info "[DRY RUN] Would run: apt-get install -y unattended-upgrades"
        return 0
    fi

    wait_for_apt_lock

    if [[ "$QUIET" -eq 0 ]]; then
        echo "Updating package lists..."
    fi
    if ! apt-get update -y; then
        log_error "Failed to update package lists"
        exit 1
    fi
    log_info "Package lists updated successfully"

    if dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q "install ok installed"; then
        log_info "unattended-upgrades is already installed"
    else
        if [[ "$QUIET" -eq 0 ]]; then
            echo "Installing unattended-upgrades..."
        fi
        if ! apt-get install -y unattended-upgrades; then
            log_error "Failed to install unattended-upgrades"
            exit 1
        fi
        mark_changed "Installed unattended-upgrades package"
        log_info "unattended-upgrades installed successfully"
    fi

    if [[ "$QUIET" -eq 0 ]]; then
        echo ""
    fi
}

# =============================================================================
# CONFIGURE UNATTENDED UPGRADES
# =============================================================================
configure_unattended_upgrades() {
    log_info "Configuring unattended-upgrades..."
    if [[ "$QUIET" -eq 0 ]]; then
        echo "--- Configuring unattended-upgrades ---"
    fi

    local config_file="/etc/apt/apt.conf.d/50unattended-upgrades"
    local new_config=""

    if [[ "$DISTRO_ID" == "ubuntu" ]]; then
        new_config=$(cat << EOFCONFIG
// Unattended-Upgrade configuration for Ubuntu
// Generated by setup_auto_updates.sh v${VERSION}
// Date: $(date '+%Y-%m-%d %H:%M:%S')

Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
//  "\${distro_id}:\${distro_codename}-updates";
//  "\${distro_id}:\${distro_codename}-proposed";
//  "\${distro_id}:\${distro_codename}-backports";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
// Unattended-Upgrade::Automatic-Reboot-Time "02:00";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
Unattended-Upgrade::DevRelease "false";
EOFCONFIG
)
    elif [[ "$DISTRO_ID" == "debian" ]]; then
        new_config=$(cat << EOFCONFIG
// Unattended-Upgrade configuration for Debian
// Generated by setup_auto_updates.sh v${VERSION}
// Date: $(date '+%Y-%m-%d %H:%M:%S')

Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${DISTRO_CODENAME},label=Debian";
    "origin=Debian,codename=${DISTRO_CODENAME},label=Debian-Security";
    "origin=Debian,codename=${DISTRO_CODENAME}-security,label=Debian-Security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
// Unattended-Upgrade::Automatic-Reboot-Time "02:00";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
EOFCONFIG
)
    else
        log_error "Unsupported distribution for configuration: ${DISTRO_ID}"
        exit 1
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[DRY RUN] Would configure ${config_file} for ${DISTRO_ID}"
        return 0
    fi

    if files_differ "$new_config" "$config_file"; then
        backup_config "50unattended-upgrades"
        echo "$new_config" > "$config_file"
        mark_changed "Updated ${config_file}"
        log_info "Configuration written to ${config_file}"
        if [[ "$QUIET" -eq 0 ]]; then
            echo "  Configuration written: /etc/apt/apt.conf.d/50unattended-upgrades"
        fi
    else
        log_info "Configuration unchanged (already up to date)"
        if [[ "$QUIET" -eq 0 ]]; then
            echo "  Configuration unchanged: /etc/apt/apt.conf.d/50unattended-upgrades"
        fi
    fi

    if [[ "$QUIET" -eq 0 ]]; then
        echo ""
    fi
}

# =============================================================================
# CONFIGURE AUTO UPGRADES SCHEDULE
# =============================================================================
configure_auto_upgrades() {
    log_info "Configuring automatic upgrade schedule..."

    local config_file="/etc/apt/apt.conf.d/20auto-upgrades"
    local new_config
    new_config=$(cat << EOFCONFIG
// Automatic upgrade schedule
// Generated by setup_auto_updates.sh v${VERSION}
// Date: $(date '+%Y-%m-%d %H:%M:%S')

APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOFCONFIG
)

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[DRY RUN] Would configure ${config_file}"
        return 0
    fi

    if files_differ "$new_config" "$config_file"; then
        backup_config "20auto-upgrades"
        echo "$new_config" > "$config_file"
        mark_changed "Updated ${config_file}"
        log_info "Schedule configured: daily updates, weekly autoclean"
        if [[ "$QUIET" -eq 0 ]]; then
            echo "  Schedule configured: /etc/apt/apt.conf.d/20auto-upgrades"
            echo "    - Daily package list updates"
            echo "    - Daily unattended upgrades"
            echo "    - Weekly autoclean (7 days)"
        fi
    else
        log_info "Schedule unchanged (already up to date)"
        if [[ "$QUIET" -eq 0 ]]; then
            echo "  Schedule unchanged: /etc/apt/apt.conf.d/20auto-upgrades"
        fi
    fi

    if [[ "$QUIET" -eq 0 ]]; then
        echo ""
    fi
}

# =============================================================================
# TEST CONFIGURATION
# =============================================================================
test_configuration() {
    log_info "Testing unattended-upgrades configuration..."
    if [[ "$QUIET" -eq 0 ]]; then
        echo "--- Testing configuration ---"
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[DRY RUN] Would run: unattended-upgrades --dry-run"
        return 0
    fi

    local output
    if output=$(unattended-upgrades --dry-run 2>&1); then
        log_info "Dry-run test completed successfully"
        if [[ "$QUIET" -eq 0 ]]; then
            echo "  Configuration test: PASSED"
        fi
    else
        log_warn "Dry-run test reported issues (may be normal on fresh systems)"
        log_warn "Dry-run output: ${output}"
        if [[ "$QUIET" -eq 0 ]]; then
            echo "  Configuration test: WARNING (non-fatal)"
            echo "  Note: This is expected on systems with no pending updates."
        fi
    fi
    if [[ "$QUIET" -eq 0 ]]; then
        echo ""
    fi
}

# =============================================================================
# ENABLE AND START SERVICE
# =============================================================================
enable_service() {
    if [[ "$HAS_SYSTEMD" -eq 0 ]]; then
        log_warn "systemd not available — skipping service enable/start"
        return 0
    fi

    log_info "Enabling and starting unattended-upgrades service..."
    if [[ "$QUIET" -eq 0 ]]; then
        echo "--- Enabling service ---"
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[DRY RUN] Would run: systemctl enable unattended-upgrades"
        log_info "[DRY RUN] Would run: systemctl start unattended-upgrades"
        return 0
    fi

    local was_enabled=0
    if systemctl is-enabled --quiet unattended-upgrades 2>/dev/null; then
        was_enabled=1
    fi

    if ! systemctl enable unattended-upgrades; then
        log_error "Failed to enable unattended-upgrades service"
        exit 1
    fi
    log_info "Service enabled"

    if [[ "$was_enabled" -eq 0 ]]; then
        mark_changed "Enabled unattended-upgrades service"
    fi

    if ! systemctl start unattended-upgrades 2>/dev/null; then
        log_warn "Failed to start unattended-upgrades immediately (may start on next timer)"
        if [[ "$QUIET" -eq 0 ]]; then
            echo "  Service enabled: yes"
            echo "  Service started: WARNING (will activate on next scheduled run)"
        fi
    else
        log_info "Service started successfully"
        if [[ "$QUIET" -eq 0 ]]; then
            echo "  Service enabled: yes"
            echo "  Service started: yes"
        fi
    fi
    if [[ "$QUIET" -eq 0 ]]; then
        echo ""
    fi
}

# =============================================================================
# CHECK STATUS
# =============================================================================
check_status() {
    if [[ "$HAS_SYSTEMD" -eq 0 ]]; then
        return 0
    fi

    log_info "Checking unattended-upgrades service status..."
    if [[ "$QUIET" -eq 0 ]]; then
        echo "--- Service status ---"
    fi

    local active_state sub_state load_state unit_file_state
    active_state=$(systemctl show unattended-upgrades --property=ActiveState --value 2>/dev/null || echo "unknown")
    sub_state=$(systemctl show unattended-upgrades --property=SubState --value 2>/dev/null || echo "unknown")
    load_state=$(systemctl show unattended-upgrades --property=LoadState --value 2>/dev/null || echo "unknown")
    unit_file_state=$(systemctl show unattended-upgrades --property=UnitFileState --value 2>/dev/null || echo "unknown")

    if [[ "$QUIET" -eq 0 ]]; then
        echo "  Active State:   ${active_state}"
        echo "  Sub State:      ${sub_state}"
        echo "  Load State:     ${load_state}"
        echo "  Unit File:      ${unit_file_state}"

        if systemctl is-enabled --quiet unattended-upgrades 2>/dev/null; then
            echo "  Enabled:        yes (will start on boot)"
        else
            echo "  Enabled:        no (will NOT start on boot)"
        fi
    fi

    log_debug "Service status: ActiveState=${active_state}, SubState=${sub_state}, LoadState=${load_state}, UnitFileState=${unit_file_state}"
    if [[ "$QUIET" -eq 0 ]]; then
        echo ""
    fi
}

# =============================================================================
# SUMMARY
# =============================================================================
show_summary() {
    if [[ "$QUIET" -eq 0 ]]; then
        echo "============================================================"
        echo "  Setup Complete"
        echo "============================================================"
        echo ""
        echo "Distribution:  ${DISTRO_NAME} ${DISTRO_VERSION_ID} (${DISTRO_CODENAME})"
        echo "Version:       ${VERSION}"
        echo "Log file:      ${LOG_FILE}"
        echo ""
        echo "Configuration files:"
        echo "  /etc/apt/apt.conf.d/50unattended-upgrades"
        echo "  /etc/apt/apt.conf.d/20auto-upgrades"
        echo ""
        echo "Backups (if applicable):"
        echo "  /etc/apt/apt.conf.d/*.${BACKUP_SUFFIX}"
        echo ""
        echo "Verify the setup with:"
        echo "  systemctl status unattended-upgrades"
        echo "  journalctl -u unattended-upgrades"
        echo "  cat /var/log/unattended-upgrades/unattended-upgrades.log"
        echo ""
        echo "============================================================"
    fi

    # Idempotency marker for Ansible / automation tools
    if [[ "$CHANGES_MADE" -eq 1 ]]; then
        echo "STATUS: CHANGED"
        log_info "Setup completed successfully (changes made)"
    else
        echo "STATUS: UNCHANGED"
        log_info "Setup completed successfully (no changes needed)"
    fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    parse_args "$@"
    log_init
    acquire_lock

    show_banner
    check_root
    detect_systemd
    detect_distribution
    check_existing_configuration
    prompt_confirmation
    install_packages
    configure_unattended_upgrades
    configure_auto_upgrades
    test_configuration
    enable_service
    check_status
    show_summary
}

main "$@"
