# AGENTS.md — AI Assistant Context

## Skills
This project includes agent-agnostic skills in the `skills/` directory.
Any AI assistant should parse files there for specialized task instructions.
- `skills/release.md` — Release preparation workflow

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
ansible/
  playbook.yml              # Sample Ansible playbook
  roles/unattended_updates/ # Ansible role
.github/workflows/
  update_changelog.yml
```

## Conventions

### VERSION
- `VERSION="3.1.0"` at top of script is single source of truth.
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
- `-y` / `--yes`: non-interactive; `-n` / `--dry-run`: validate only; `-q` / `--quiet`: minimal output; `-v` / `--verbose`: debug; `-l <path>` / `--log-file`: custom log; `-h` / `--help`: usage.
- Parsed in `parse_args()` via `case`.

### Distro Detection
- Read `/etc/os-release`; never assume.
- Associative arrays for supported versions.
- Ubuntu: `Unattended-Upgrade::Allowed-Origins { ... }`
- Debian: `Unattended-Upgrade::Origins-Pattern { ... }`
- Reject unsupported with clear error.

### Idempotency
- Package installation skips if already present.
- Config files compared with `files_differ()` before writing.
- Service enablement only marks changed if not previously enabled.
- Final output: `STATUS: CHANGED` or `STATUS: UNCHANGED`.

### Lock File
- Use `/var/run/setup_auto_updates.sh.lock` to prevent concurrent runs.
- Remove in `cleanup()` trap on EXIT.

### Systemd Detection
- Detect via `systemctl >/dev/null 2>&1` before any service commands.
- If absent (containers), skip enable/start but still write configs.
- Set `HAS_SYSTEMD=1/0` flag; gate all service functions with it.

### APT Lock Wait
- Wait up to 300s for `/var/lib/dpkg/lock{,-frontend}` and `/var/lib/apt/lists/lock` to clear.
- Use `fuser` to detect holding processes.
- Fail with clear error if lock persists beyond timeout.

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
