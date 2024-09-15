#!/bin/bash

# Script: Automatic Security Updates Setup for Ubuntu 22.04+ and Debian 12+
# Version: 2.1
# Author: Ruhani Rabin
# Date: Sunday, September 15, 2024
#
# Description: This script sets up automatic security updates using unattended-upgrades on Ubuntu 22.04+ and Debian 12+.
# It installs necessary packages, configures unattended-upgrades, and sets up periodic updates.
#
# WARNING: This script will overwrite existing configuration files. If you have custom configurations,
# please back them up before running this script.

# Clear the screen
clear

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
echo "Version: 2.1"
echo "Author: Ruhani Rabin"
echo "Date: $(date +%Y-%m-%d)"
echo

# Exit on any error
set -e

# Function to check if the script is run as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "❌ This script must be run as root" 1>&2
        exit 1
    fi
}

# Function to check if unattended-upgrades is already configured
check_existing_configuration() {
    if systemctl is-active --quiet unattended-upgrades; then
        echo ""
        echo "█████████████████████████████████████████████████████"
        echo "██                                                 ██"
        echo "██  Unattended-upgrades service is already active. ██"
        echo "██                                                 ██"
        echo "█████████████████████████████████████████████████████"
        echo ""
        read -p "░░░ Do you want to continue and potentially overwrite existing configurations? (y/N): ░░░" response
        case "$response" in
            [yY][eE][sS]|[yY]) 
                echo "✓ Proceeding with the setup..."
                ;;
            *)
                echo "❌ Setup cancelled. Existing configuration will be maintained."
                exit 0
                ;;
        esac
    else
        echo ""
        echo "░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░"
        echo "░░░                                                         ░░░"
        echo "░░░ No existing unattended-upgrades configuration detected. ░░░"
        echo "░░░ Proceeding with setup...                                ░░░"
        echo "░░░                                                         ░░░"
        echo "░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░"
        echo ""
    fi
}

# Function to prompt for confirmation
prompt_confirmation() {
    read -p "░░░ This script may overwrite existing configurations. Do you want to continue? (y/N): ░░░" response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "✓ Proceeding with the setup..."
            ;;
        *)
            echo "❌ Setup cancelled."
            exit 0
            ;;
    esac
}

# Function to show spinner
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Function to install necessary packages
install_packages() {
    echo "Updating package lists..."
    apt-get update > /dev/null 2>&1 &
    spinner $!

    echo "Installing unattended-upgrades and apt-listchanges..."
    apt-get install unattended-upgrades apt-listchanges -y > /dev/null 2>&1 &
    spinner $!

    if [ $? -eq 0 ]; then
        echo "✓ Packages installed successfully."
    else
        echo "❌ Error installing packages. Please check your internet connection and try again."
        exit 1
    fi
}

# Function to detect the distribution
detect_distribution() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        echo "❌ Unable to detect distribution. Exiting."
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
        echo "❌ Unsupported distribution: $DISTRO. Exiting."
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
echo "Testing unattended-upgrades configuration..."
    if output=$(unattended-upgrades --dry-run 2>&1); then
        echo "✓ Success: Unattended-upgrades dry run completed without errors."
    else
        echo "❌ Error: Unattended-upgrades dry run encountered issues. Please check your configuration."
        echo "You can run 'sudo unattended-upgrades --dry-run' manually for more details."
    fi
}

# Function to enable and start the service with spinner
enable_service() {
    echo "Enabling and starting unattended upgrades service..."
    
    # Start the service in the background
    (systemctl enable unattended-upgrades && systemctl start unattended-upgrades) > /dev/null 2>&1 &
    
    # Get the PID of the background process
    local pid=$!
    
    # Show spinner while the service is being enabled and started
    spinner $pid
    
    # Wait for the background process to finish
    wait $pid
    
    # Check if the service was successfully enabled and started
    if systemctl is-active --quiet unattended-upgrades; then
        echo "✓ Unattended upgrades service has been successfully enabled and started."
    else
        echo "❌ Failed to enable and start unattended upgrades service. Please check system logs for details."
    fi
}

# Function to check the status of the service
check_status() {
    echo "Checking status of unattended-upgrades service:"
    
    # Use systemctl show to get all relevant information
    status_output=$(systemctl show unattended-upgrades --property=ActiveState,SubState,LoadState,UnitFileState)

    # Parse and display the output
    while IFS='=' read -r key value; do
        case "$key" in
            "ActiveState")
                echo "» Active State: $value"
                ;;
            "SubState")
                echo "» Sub State: $value"
                ;;
            "LoadState")
                echo "» Load State: $value"
                ;;
            "UnitFileState")
                echo "» Unit File State: $value"
                ;;
        esac
    done <<< "$status_output"

    # Check if the service is enabled
    if systemctl is-enabled --quiet unattended-upgrades; then
        echo "✓ Service is enabled (will start on boot)"
    else
        echo "❌ Service is not enabled (won't start on boot)"
    fi
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

echo "✓ Automatic security updates setup complete!"
