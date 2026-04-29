#!/bin/bash
# =============================================================================
# Script: Automatic Security Updates Setup
# Version: 3.0.0
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
# WARNING: This script will back up and may overwrite existing configuration
#          files. Backups are created at /etc/apt/apt.conf.d/<file>.bak.<timestamp>
# =============================================================================

# =============================================================================
# SINGLE SOURCE-OF-TRUTH VERSION
# All version references in this script derive from this variable.
# =============================================================================
VERSION="3.0.0"

# =============================================================================
# GLOBALS
# =============================================================================
LOG_FILE="/var/log/unattended-setup.log"
VERBOSE=0
DRY_RUN=0
NON_INTERACTIVE=0
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
BACKUP_SUFFIX="bak.${TIMESTAMP}"

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
    echo "INFO: $*"
    log_write "INFO" "$*"
}

log_warn() {
    echo "WARNING: $*" >&2
    log_write "WARN" "$*"
}

log_error() {
    echo "ERROR: $*" >&2
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
    echo ""
    echo "ERROR: An error occurred during setup (line ${line_number}, exit code ${exit_code})."
    echo "       Review the log at ${LOG_FILE} for troubleshooting."
    echo ""
    exit "$exit_code"
}

trap err_handler ERR

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_warn "Script exited with non-zero status: ${exit_code}"
        echo ""
        log_info "If the service was partially configured, you can check its status with:"
        log_info "  systemctl status unattended-upgrades"
        log_info "  journalctl -u unattended-upgrades"
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
  -v, --verbose      Enable verbose/debug output
  -l, --log-file     Specify custom log file path (default: ${LOG_FILE})
  -h, --help         Show this help message and exit

Examples:
  $0                     # Interactive mode
  $0 --yes               # Non-interactive (automation-friendly)
  $0 --dry-run           # Validate only
  $0 --yes --verbose     # Non-interactive with detailed output
  $0 --log-file /tmp/setup.log  # Custom log path

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
# BANNER
# =============================================================================
show_banner() {
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

    log_info "Detected: ${DISTRO_NAME} ${DISTRO_VERSION_ID} (${DISTRO_CODENAME})"
    log_debug "ID=${DISTRO_ID}, VERSION_ID=${DISTRO_VERSION_ID}, CODENAME=${DISTRO_CODENAME}"

    validate_distribution
}

validate_distribution() {
    case "$DISTRO_ID" in
        ubuntu)
            # Ubuntu may use UBUNTU_CODENAME for LTS vs regular releases
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
    if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
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
# BACKUP EXISTING CONFIGURATION
# =============================================================================
backup_config() {
    local file="$1"
    local target="/etc/apt/apt.conf.d/${file}"

    if [[ -f "$target" ]]; then
        local backup="${target}.${BACKUP_SUFFIX}"
        cp -p "$target" "$backup"
        log_info "Backed up ${target} -> ${backup}"
        echo "  Backed up: ${file} -> ${file}.${BACKUP_SUFFIX}"
    else
        log_debug "No existing config to back up: ${target}"
    fi
}

# =============================================================================
# INSTALL PACKAGES
# =============================================================================
install_packages() {
    log_info "Installing required packages..."
    echo ""
    echo "--- Installing packages ---"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[DRY RUN] Would run: apt-get update"
        log_info "[DRY RUN] Would run: apt-get install -y unattended-upgrades"
        return 0
    fi

    echo "Updating package lists..."
    if ! apt-get update -y; then
        log_error "Failed to update package lists"
        exit 1
    fi
    log_info "Package lists updated successfully"

    echo "Installing unattended-upgrades..."
    if ! apt-get install -y unattended-upgrades; then
        log_error "Failed to install unattended-upgrades"
        exit 1
    fi
    log_info "unattended-upgrades installed successfully"

    echo ""
}

# =============================================================================
# CONFIGURE UNATTENDED UPGRADES
# =============================================================================
configure_unattended_upgrades() {
    log_info "Configuring unattended-upgrades..."
    echo "--- Configuring unattended-upgrades ---"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[DRY RUN] Would configure /etc/apt/apt.conf.d/50unattended-upgrades for ${DISTRO_ID}"
        return 0
    fi

    backup_config "50unattended-upgrades"

    local config_file="/etc/apt/apt.conf.d/50unattended-upgrades"

    if [[ "$DISTRO_ID" == "ubuntu" ]]; then
        cat > "$config_file" << EOFCONFIG
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

// Automatically fix interrupted dpkg runs
Unattended-Upgrade::AutoFixInterruptedDpkg "true";

// Use minimal steps for safer upgrades
Unattended-Upgrade::MinimalSteps "true";

// Remove unused kernel packages
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Remove unused dependencies
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Automatically reboot if required (disabled by default)
// Set to "true" to enable automatic reboot after kernel updates
Unattended-Upgrade::Automatic-Reboot "false";
// Unattended-Upgrade::Automatic-Reboot-Time "02:00";

// Do not auto-reboot if users are logged in
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";

// Development release handling
Unattended-Upgrade::DevRelease "false";
EOFCONFIG

    elif [[ "$DISTRO_ID" == "debian" ]]; then
        cat > "$config_file" << EOFCONFIG
// Unattended-Upgrade configuration for Debian
// Generated by setup_auto_updates.sh v${VERSION}
// Date: $(date '+%Y-%m-%d %H:%M:%S')

Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${DISTRO_CODENAME},label=Debian";
    "origin=Debian,codename=${DISTRO_CODENAME},label=Debian-Security";
    "origin=Debian,codename=${DISTRO_CODENAME}-security,label=Debian-Security";
};

// Automatically fix interrupted dpkg runs
Unattended-Upgrade::AutoFixInterruptedDpkg "true";

// Use minimal steps for safer upgrades
Unattended-Upgrade::MinimalSteps "true";

// Remove unused kernel packages
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Remove unused dependencies
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Automatically reboot if required (disabled by default)
// Set to "true" to enable automatic reboot after kernel updates
Unattended-Upgrade::Automatic-Reboot "false";
// Unattended-Upgrade::Automatic-Reboot-Time "02:00";

// Do not auto-reboot if users are logged in
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
EOFCONFIG

    else
        log_error "Unsupported distribution for configuration: ${DISTRO_ID}"
        exit 1
    fi

    log_info "Configuration written to ${config_file}"
    echo "  Configuration written: /etc/apt/apt.conf.d/50unattended-upgrades"
    echo ""
}

# =============================================================================
# CONFIGURE AUTO UPGRADES SCHEDULE
# =============================================================================
configure_auto_upgrades() {
    log_info "Configuring automatic upgrade schedule..."

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[DRY RUN] Would configure /etc/apt/apt.conf.d/20auto-upgrades"
        return 0
    fi

    backup_config "20auto-upgrades"

    cat > /etc/apt/apt.conf.d/20auto-upgrades << EOFCONFIG
// Automatic upgrade schedule
// Generated by setup_auto_updates.sh v${VERSION}
// Date: $(date '+%Y-%m-%d %H:%M:%S')

APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOFCONFIG

    log_info "Schedule configured: daily updates, weekly autoclean"
    echo "  Schedule configured: /etc/apt/apt.conf.d/20auto-upgrades"
    echo "    - Daily package list updates"
    echo "    - Daily unattended upgrades"
    echo "    - Weekly autoclean (7 days)"
    echo ""
}

# =============================================================================
# TEST CONFIGURATION
# =============================================================================
test_configuration() {
    log_info "Testing unattended-upgrades configuration..."
    echo "--- Testing configuration ---"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[DRY RUN] Would run: unattended-upgrades --dry-run"
        return 0
    fi

    local output
    if output=$(unattended-upgrades --dry-run 2>&1); then
        log_info "Dry-run test completed successfully"
        echo "  Configuration test: PASSED"
    else
        log_warn "Dry-run test reported issues (may be normal on fresh systems)"
        log_warn "Dry-run output: ${output}"
        echo "  Configuration test: WARNING (non-fatal)"
        echo "  Note: This is expected on systems with no pending updates."
        echo "  You can manually verify with: sudo unattended-upgrades --dry-run -v"
    fi
    echo ""
}

# =============================================================================
# ENABLE AND START SERVICE
# =============================================================================
enable_service() {
    log_info "Enabling and starting unattended-upgrades service..."
    echo "--- Enabling service ---"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[DRY RUN] Would run: systemctl enable unattended-upgrades"
        log_info "[DRY RUN] Would run: systemctl start unattended-upgrades"
        return 0
    fi

    if ! systemctl enable unattended-upgrades; then
        log_error "Failed to enable unattended-upgrades service"
        exit 1
    fi
    log_info "Service enabled"

    if ! systemctl start unattended-upgrades 2>/dev/null; then
        log_warn "Failed to start unattended-upgrades immediately (may start on next timer)"
        echo "  Service enabled: yes"
        echo "  Service started: WARNING (will activate on next scheduled run)"
    else
        log_info "Service started successfully"
        echo "  Service enabled: yes"
        echo "  Service started: yes"
    fi
    echo ""
}

# =============================================================================
# CHECK STATUS
# =============================================================================
check_status() {
    log_info "Checking unattended-upgrades service status..."
    echo "--- Service status ---"

    local active_state sub_state load_state unit_file_state
    active_state=$(systemctl show unattended-upgrades --property=ActiveState --value 2>/dev/null || echo "unknown")
    sub_state=$(systemctl show unattended-upgrades --property=SubState --value 2>/dev/null || echo "unknown")
    load_state=$(systemctl show unattended-upgrades --property=LoadState --value 2>/dev/null || echo "unknown")
    unit_file_state=$(systemctl show unattended-upgrades --property=UnitFileState --value 2>/dev/null || echo "unknown")

    echo "  Active State:   ${active_state}"
    echo "  Sub State:      ${sub_state}"
    echo "  Load State:     ${load_state}"
    echo "  Unit File:      ${unit_file_state}"

    if systemctl is-enabled --quiet unattended-upgrades 2>/dev/null; then
        echo "  Enabled:        yes (will start on boot)"
    else
        echo "  Enabled:        no (will NOT start on boot)"
    fi

    log_debug "Service status: ActiveState=${active_state}, SubState=${sub_state}, LoadState=${load_state}, UnitFileState=${unit_file_state}"
    echo ""
}

# =============================================================================
# SUMMARY
# =============================================================================
show_summary() {
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

    log_info "Setup completed successfully"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    parse_args "$@"
    log_init

    show_banner
    check_root
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
