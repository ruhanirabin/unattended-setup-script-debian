#!/bin/bash

# Script: Automatic Security Updates Setup for Ubuntu 22.04+ and Debian 12+
# Version: 1.3
# Author: Ruhani Rabin
# Date: $(date +%Y-%m-%d)
#
# Description: This script sets up automatic security updates using unattended-upgrades on Ubuntu 22.04+ and Debian 12+.
# It installs necessary packages, configures unattended-upgrades, and sets up periodic updates.
#
# WARNING: This script will overwrite existing configuration files. If you have custom configurations,
# please back them up before running this script.

# Display ASCII art
cat << "EOF"
██╗   ██╗ █████╗     ███████╗███████╗████████╗██╗   ██╗██████╗ 
██║   ██║██╔══██╗    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
██║   ██║███████║    ███████╗█████╗     ██║   ██║   ██║██████╔╝
██║   ██║██╔══██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ 
╚██████╔╝██║  ██║    ███████║███████╗   ██║   ╚██████╔╝██║     
 ╚═════╝ ╚═╝  ╚═╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     
                                                              
EOF

echo "Automatic Security Updates Setup for Ubuntu 22.04+ or Debian 12+"
echo "Version: 1.3"
echo "Author: Ruhani Rabin"
echo "Date: $(date +%Y-%m-%d)"
echo

# Exit on any error
set -e

# Function to check if the script is run as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" 1>&2
        exit 1
    fi
}

# Function to check if unattended-upgrades is already configured
check_existing_configuration() {
    if systemctl is-active --quiet unattended-upgrades; then
        echo "Unattended-upgrades service is already active."
        read -p "Do you want to continue and potentially overwrite existing configurations? (y/N): " response
        case "$response" in
            [yY][eE][sS]|[yY]) 
                echo "Proceeding with the setup..."
                ;;
            *)
                echo "Setup cancelled. Existing configuration will be maintained."
                exit 0
                ;;
        esac
    else
        echo "No existing unattended-upgrades configuration detected. Proceeding with setup..."
    fi
}

# Function to prompt for confirmation
prompt_confirmation() {
    read -p "This script may overwrite existing configurations. Do you want to continue? (y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "Proceeding with the setup..."
            ;;
        *)
            echo "Setup cancelled."
            exit 0
            ;;
    esac
}

# Function to install necessary packages
install_packages() {
    apt-get update
    apt-get install unattended-upgrades apt-listchanges -y
}

# Function to detect the distribution
detect_distribution() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        echo "Unable to detect distribution. Exiting."
        exit 1
    fi
}

# Function to configure unattended-upgrades
configure_unattended_upgrades() {
    detect_distribution

    if [ "$DISTRO" = "ubuntu" ]; then
        cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}:\${distro_codename}-updates";
};
EOF
    elif [ "$DISTRO" = "debian" ]; then
        cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
        "\${distro_id}:\${distro_codename}";
        "\${distro_id}:\${distro_codename}-security";
        "\${distro_id}ESMApps:\${distro_codename}-apps-security";
        "\${distro_id}ESM:\${distro_codename}-infra-security";
        "\${distro_id}:\${distro_codename}-updates";
//      "\${distro_id}:\${distro_codename}-proposed";
//      "\${distro_id}:\${distro_codename}-backports";
};
EOF
    else
        echo "Unsupported distribution: $DISTRO. Exiting."
        exit 1
    fi

    # Common configuration for both distributions
    cat >> /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
}

# Function to configure automatic upgrades
configure_auto_upgrades() {
    cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
}

# Function to configure update intervals and behaviors
configure_periodic() {
    cat > /etc/apt/apt.conf.d/10periodic << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
}

# Function to test the configuration
test_configuration() {
    unattended-upgrades --dry-run --debug
}

# Function to enable and start the service
enable_service() {
    systemctl enable unattended-upgrades
    systemctl start unattended-upgrades
}

# Function to check the status of the service
check_status() {
    systemctl status unattended-upgrades
}

# Main function to run all steps
main() {
    check_root
    check_existing_configuration
    prompt_confirmation
    install_packages
    configure_unattended_upgrades
    configure_auto_upgrades
    configure_periodic
    test_configuration
    enable_service
    check_status
}

# Run the main function
main

echo "Automatic security updates setup complete!"
