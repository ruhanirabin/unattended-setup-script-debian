# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.0.0] - 2026-04-29

### Added
- Single source-of-truth `VERSION` variable for consistent version tracking
- Comprehensive logging system with `log_info()`, `log_warn()`, `log_error()`, `log_debug()` functions
- Log output to `/var/log/unattended-setup.log` by default
- CLI flags: `--yes`/`-y` (non-interactive), `--dry-run`/`-n` (validate only), `--verbose`/`-v`, `--log-file`/`-l`, `--help`/`-h`
- Graceful error handling with `trap` and actionable error messages
- Automatic backup of existing configuration files before overwriting
- Post-setup service status verification
- Support for Ubuntu 24.04, 24.10, 25.04, 25.10, 26.04, 26.10
- Support for Debian 13 (Trixie), 14 (Forky), Sid (Unstable)
- `AutoFixInterruptedDpkg` and `MinimalSteps` options for reliability
- Configurable automatic reboot settings (disabled by default)

### Changed
- Replaced `set -e` with custom error handler via `trap err_handler ERR`
- Removed redundant `10periodic` configuration (settings duplicated in `20auto-upgrades`)
- Removed animated progress bar (obscures real output and breaks CI/CD)
- Removed `clear` command at startup
- Removed `> /dev/null 2>&1` from apt-get commands for transparency
- Changed license from GPL v3 to MIT
- Updated GitHub workflow to use `actions/checkout@v4`

### Fixed
- **Critical**: Fixed Debian configuration syntax to use `Origins-Pattern` instead of `Allowed-Origins`
- Fixed version extraction in GitHub workflow to handle `VERSION="x.y.z"` format
- Fixed configuration conflicts between `20auto-upgrades` and `10periodic`
- Improved distribution detection with fallbacks for Ubuntu codenames

### Removed
- GPL v3 license (replaced with MIT)
- `apt-listchanges` from mandatory package installation (optional dependency)
- Redundant `10periodic` configuration file creation

## [2.4.3] - 2024-10-10

### Added
- GitHub Actions automation for README changelog updates

## [2.4.2] - 2024-10-10

### Changed
- Added more instructions where needed
- Added GitHub hooks

## [2.4.1] - 2024-10-10

### Changed
- Removed typical updates, only keeps security updates
- Changed ASCII art to match the script name
