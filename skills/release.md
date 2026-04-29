---
description: Prepare a new release — bump version, validate, commit, tag
---

Prepare a release by bumping the VERSION file, validating all artifacts, and committing.

## Steps

1. Read `VERSION` file in the project root to determine the current version
2. Ask the user for the new version (or infer as patch/minor/major bump)
3. Run `bash scripts/bump-version.sh <new-version>` to update `VERSION` and dependent files
4. Run `bash scripts/validate-version.sh` to confirm all dependent files reflect the new version
5. Run `shellcheck setup_auto_updates.sh` if available; fix any issues
6. Stage all changes and commit with a short imperative message
7. Tag the commit with the version string
8. Optionally trigger the release pipeline (`bash scripts/release.sh`)

## Rules

- Never manually edit version numbers in any file; always use `scripts/bump-version.sh`
- Treat `VERSION` as immutable outside the release bump process
- Keep commit messages ≤50 characters (subject line)
- Use imperative mood (e.g., "Bump version to 3.2.0")
- Do not push automatically — only commit and tag locally
- If `shellcheck` is not installed, warn but do not fail
- Post-release, run `bash scripts/validate-version.sh` to verify consistency across all artifacts

## Windows Note

All release scripts are written in bash and **must** be invoked with bash:
- **Windows:** `bash scripts/bump-version.sh patch`, `bash scripts/release.sh patch`
- **Linux / macOS:** `bash scripts/release.sh patch` (or `./scripts/release.sh` if executable)
