# Automatic unattended security updates setup for ubuntu 22+ or debian 12+ - shell script

A script that automates the process of setting up unattended security updates on Ubuntu 22.04 and newer versions. This script ensures your system stays secure by automatically installing important security updates.

## What Does This Script Do?

1. Checks if it's running with root privileges
2. Verifies if unattended-upgrades is already set up
3. Installs necessary packages
4. Configures unattended-upgrades
5. Sets up automatic upgrades
6. Configures update intervals
7. Tests the configuration
8. Enables and starts the unattended-upgrades service

## How to Use This Script

You can copy this line below run this script directly from a Root shell:

```bash

sudo bash -c "$(curl -fsSL https://github.com/ruhanirabin/unattended-setup-script-debian/raw/main/setup_auto_updates.sh)"
```

## Screenshot
![automatic-unattended-security-updates-setup-screenshot](https://github.com/user-attachments/assets/15da9528-58e8-4a80-a70a-10541c9ffc06)


## Important Notes

- This script will overwrite existing configuration files. If you have custom configurations, back them up before running this script.
- Running scripts directly from the internet can be a security risk. Always verify the source and content of the script before running it.
- After setting up automatic updates, monitor your system to ensure it's functioning as expected.

By using this script, you can quickly and easily set up automatic security updates on your Ubuntu 22.04+ or Debian 12 system, helping to keep it secure with minimal manual intervention.
