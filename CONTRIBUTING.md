# Contributing

Thank you for improving `srm-dhcp-export`.

## Development setup

Install the runtime dependencies described in `README.md`, then run:

```bash
./srm-dhcp-export.sh --check-dependencies
./tests/run.sh
```

Install ShellCheck for shell linting when available.

## Pull requests

1. Create a focused branch from the default branch.
2. Keep user-facing text, code, comments, documentation, and tests in English.
3. Preserve Bash 3.2 compatibility unless a major version explicitly changes that requirement.
4. Avoid disabling SSH host-key checking or weakening file permissions.
5. Add or update tests for behavioral changes.
6. Run `make check` and `make test` before opening the pull request.
7. Update `CHANGELOG.md` for user-visible changes.
8. Use clear commit messages and explain security implications in the pull request description.

## Coding conventions

- Shell scripts use four-space indentation and `set -Eeuo pipefail` where appropriate.
- Python code follows PEP 8 and uses only the standard library except for WeasyPrint.
- CSS custom properties should be used for theme-level changes.
- Source files should include `SPDX-License-Identifier: LGPL-3.0-only` where the format permits comments.
- Do not add telemetry, credential collection, or network calls unrelated to the requested SSH export.

## License of contributions

By submitting a contribution, you agree that it may be distributed under the project's `LGPL-3.0-only` license.
