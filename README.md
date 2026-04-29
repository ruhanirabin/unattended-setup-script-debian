# Automatic Security Updates Setup Script

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-3.0.0-blue.svg)](CHANGELOG.md)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%20%7C%2024.10%20%7C%2025.04%20%7C%2025.10%20%7C%2026.04%20%7C%2026.10-E95420)](#)
[![Debian](https://img.shields.io/badge/Debian-13%20%7C%2014%20%7C%20Sid-A81D33)](#)

A production-ready shell script that automates the setup of unattended security updates on Ubuntu and Debian servers. Keeps your systems patched against known vulnerabilities with zero manual intervention.

---

## Quick Install

Run as **root**:

```bash
sudo bash -c "$(curl -fsSL https://github.com/ruhanirabin/unattended-setup-script-debian/raw/main/setup_auto_updates.sh)"
```

For **non-interactive** (automation/Ansible/Packer):

```bash
sudo bash setup_auto_updates.sh --yes
```

---

## Requirements

- **Root access** (sudo or root user)
- **Systemd-based** Linux distribution
- **Internet connectivity** for package installation
- Minimum **50 MB** free disk space

---

## Supported Distributions

| Distribution | Versions | Codenames |
|---|---|---|
| Ubuntu | 24.04 LTS | noble |
| Ubuntu | 24.10 | oracular |
| Ubuntu | 25.04 | plucky |
| Ubuntu | 25.10 | questing |
| Ubuntu | 26.04 LTS | resolute |
| Ubuntu | 26.10 | — |
| Debian | 13 | trixie |
| Debian | 14 | forky |
| Debian | Sid (unstable) | sid |

> **Note:** Unsupported versions will be detected and rejected with a clear error message listing supported releases.

---

## What This Script Does

1. **Root verification** — ensures the script runs with elevated privileges
2. **Distribution detection** — identifies OS type, version, and codename via `/etc/os-release`
3. **Existing config check** — detects running unattended-upgrades and warns about reconfiguration
4. **Package installation** — installs `unattended-upgrades` via apt
5. **Config backup** — backs up existing APT configuration files before modification
6. **Unattended-upgrades configuration** — writes distribution-specific config (`50unattended-upgrades`)
7. **Schedule configuration** — sets daily update/check cycles (`20auto-upgrades`)
8. **Dry-run validation** — tests the configuration without applying changes
9. **Service enable/start** — enables and starts the `unattended-upgrades` systemd service
10. **Status verification** — reports service state and provides verification commands

---

## Usage

### Interactive Mode (default)

```bash
sudo bash setup_auto_updates.sh
```

Prompts for confirmation before making changes.

### Non-Interactive Mode

```bash
sudo bash setup_auto_updates.sh --yes
```

Skips all prompts. Ideal for automation, Ansible, Packer, or cloud-init.

### Dry-Run Mode

```bash
sudo bash setup_auto_updates.sh --dry-run
```

Validates the environment and shows what would be done without making any changes.

### Verbose Mode

```bash
sudo bash setup_auto_updates.sh --yes --verbose
```

Enables detailed debug output on stdout and in the log file.

### Custom Log File

```bash
sudo bash setup_auto_updates.sh --log-file /var/log/my-setup.log
```

### All Options

| Flag | Description |
|---|---|
| `-y`, `--yes` | Skip all confirmation prompts |
| `-n`, `--dry-run` | Validate only, no changes |
| `-v`, `--verbose` | Enable debug output |
| `-l`, `--log-file <path>` | Set custom log file path |
| `-h`, `--help` | Show help and exit |

---

## Configuration Details

### `/etc/apt/apt.conf.d/50unattended-upgrades`

The main unattended-upgrades configuration. This script generates a distro-specific file:

- **Ubuntu**: Uses `Allowed-Origins` with `${distro_id}:${distro_codename}-security` patterns
- **Debian**: Uses `Origins-Pattern` with `origin=Debian,codename=<codename>` patterns

**Included settings:**
- Security updates only (updates, proposed, backports commented out)
- `AutoFixInterruptedDpkg "true"` — recovers from interrupted package operations
- `MinimalSteps "true"` — safer upgrades resilient to interruptions
- `Remove-Unused-Kernel-Packages "true"` — cleans old kernels
- `Remove-Unused-Dependencies "true"` — removes orphaned packages
- `Automatic-Reboot "false"` — disabled by default for safety

**Enabling automatic reboot:**

Edit `/etc/apt/apt.conf.d/50unattended-upgrades` and change:

```
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
```

### `/etc/apt/apt.conf.d/20auto-upgrades`

Controls the periodic execution schedule:

```
APT::Periodic::Update-Package-Lists "1";       # Daily
APT::Periodic::Unattended-Upgrade "1";          # Daily
APT::Periodic::AutocleanInterval "7";           # Weekly
```

---

## Post-Installation Verification

After running the script, verify the setup:

```bash
# Check service status
systemctl status unattended-upgrades

# View service journal
journalctl -u unattended-upgrades --no-pager -n 50

# Run a dry-run test
sudo unattended-upgrades --dry-run -v

# Check the unattended-upgrades log
sudo cat /var/log/unattended-upgrades/unattended-upgrades.log

# View the script's own log
sudo cat /var/log/unattended-setup.log
```

---

## Logging

The script writes structured logs to:

- **Default path:** `/var/log/unattended-setup.log`
- **Custom path:** Use `--log-file /path/to/log`

**Log format:**

```
[YYYY-MM-DD HH:MM:SS] [LEVEL] message
```

**Levels:** INFO, WARN, ERROR, DEBUG

**Unattended-upgrades logs** (managed by the package itself):

- `/var/log/unattended-upgrades/unattended-upgrades.log`
- `/var/log/unattended-upgrades/unattended-upgrades-dpkg.log`

---

## Troubleshooting

### Service not starting

```bash
# Check journal for errors
journalctl -u unattended-upgrades -e --no-pager

# Check APT configuration syntax
sudo apt-config dump | grep -i unattended
```

### Dry-run test fails

This is normal on freshly installed systems with no pending updates. Verify with:

```bash
sudo unattended-upgrades --dry-run -v --apt-debug
```

### "Unsupported distribution" error

The script validates the OS version against a supported list. Update the script or file an issue if your version should be supported.

### Configuration not applying

Ensure no conflicting files exist in `/etc/apt/apt.conf.d/`:

```bash
ls -la /etc/apt/apt.conf.d/ | grep -E '(10periodic|20auto|50unattended)'
```

The script backs up existing files with a `.bak.<timestamp>` suffix.

### Reverting changes

See the [Uninstallation](#uninstallation) section below.

---

## Security Considerations

- **Automatic updates** can introduce regressions. Test on non-production systems first
- The script installs **security updates only** by default — it does not apply feature updates or backports
- **Kernel updates** that require a reboot will not automatically reboot the system (configurable)
- Always **review** scripts from the internet before piping them to `bash`
- Configuration files are **backed up** before modification
- The `AutoFixInterruptedDpkg` option helps recover from interrupted upgrades but may mask underlying package issues

---

## Uninstallation

To reverse all changes made by this script:

```bash
# 1. Stop and disable the service
sudo systemctl stop unattended-upgrades
sudo systemctl disable unattended-upgrades

# 2. Remove configuration files
sudo rm -f /etc/apt/apt.conf.d/20auto-upgrades
sudo rm -f /etc/apt/apt.conf.d/50unattended-upgrades

# 3. Restore backups (if available)
sudo mv /etc/apt/apt.conf.d/*.bak.* /etc/apt/apt.conf.d/ 2>/dev/null || true

# 4. Remove the package (optional)
sudo apt-get remove --purge -y unattended-upgrades
sudo apt-get autoremove -y

# 5. Remove the setup log
sudo rm -f /var/log/unattended-setup.log
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full release history.

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

## Author

**Ruhani Rabin**

---

## Contributing

Issues and pull requests are welcome. Please test any changes on both Ubuntu and Debian before submitting.
