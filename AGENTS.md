# AGENTS.md — AI Assistant Context

## Project
- `setup_auto_updates.sh` automates unattended security updates on Ubuntu (24.04+) and Debian (13+).
- Installs/configures `unattended-upgrades`, sets periodic schedules, enables systemd service.
- MIT licensed.

## Files
```
setup_auto_updates.sh       # Main script
README.md                   # User docs
CHANGELOG.md                # Keep a Changelog format
LICENSE
AGENTS.md                   # This file
.github/workflows/
  update_changelog.yml
```

## Conventions

### VERSION
- `VERSION="3.0.0"` at top of script is single source of truth.
- Derive all version refs from it; never hardcode elsewhere.

### Logging
- Functions: `log_info`, `log_warn`, `log_error`, `log_debug`.
- Format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] message`.
- Output to stdout and `LOG_FILE` (default: `/var/log/unattended-setup.log`).
- `log_debug` only when `VERBOSE=1` (`--verbose`).

### Error Handling
- No `set -e`; use `trap err_handler ERR`.
- `cleanup()` trap on EXIT for partial-state guidance.
- Critical: log error, exit non-zero. Non-critical: log warn, continue.

### CLI Flags
- `-y` / `--yes`: non-interactive; `-n` / `--dry-run`: validate only; `-v` / `--verbose`: debug; `-l <path>` / `--log-file`: custom log; `-h` / `--help`: usage.
- Parsed in `parse_args()` via `case`.

### Distro Detection
- Read `/etc/os-release`; never assume.
- Associative arrays for supported versions.
- Ubuntu: `Unattended-Upgrade::Allowed-Origins { ... }`
- Debian: `Unattended-Upgrade::Origins-Pattern { ... }`
- Reject unsupported with clear error.

### Configuration
- Only `50unattended-upgrades` and `20auto-upgrades`; never `10periodic`.
- Backup existing configs before writing.
- Use `<< EOFCONFIG` heredocs for config generation.

## Testing
- Targets Ubuntu 24.04+ / Debian 13+; manual testing requires Linux.
- Use `--dry-run` for no-side-effect validation.
- `shellcheck` recommended.
- GitHub workflow runs on `ubuntu-latest`.

## Dependencies
- `bash` 4.0+, `systemctl`, `apt-get`, `unattended-upgrades`.

## Do NOT
- Add `set -e` (use traps).
- Create `10periodic`.
- Use `> /dev/null 2>&1`.
- Hardcode versions outside `VERSION`.
- Make `apt-listchanges` mandatory.
- Add animated progress indicators.
- Write GPL code.

## Commit Messages
- Keep commit messages short and concise (≤50 chars for the subject line).
- Use imperative mood (e.g., "Fix config syntax", not "Fixed config syntax").
- Add a body only when extra context is genuinely needed.
