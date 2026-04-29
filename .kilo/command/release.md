---
description: Prepare a new release — bump version, validate, commit, tag
---

Prepare a release by bumping the VERSION variable, validating the script, and committing.

## Steps

1. Read `setup_auto_updates.sh` and extract the current `VERSION`
2. Ask the user for the new version (or infer as patch/minor/major bump)
3. Update `VERSION` in `setup_auto_updates.sh`
4. Run `shellcheck setup_auto_updates.sh` if available; fix any issues
5. Update `CHANGELOG.md` with a new section for the version
6. Update `README.md` version badge if present
7. Update `AGENTS.md` version reference if present
8. Stage all changes and commit with a short imperative message
9. Tag the commit with the version string

## Rules

- Keep commit messages ≤50 characters (subject line)
- Use imperative mood (e.g., "Bump version to 3.2.0")
- Do not push automatically — only commit and tag locally
- If `shellcheck` is not installed, warn but do not fail
