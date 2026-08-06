# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 1.0.x | Yes |
| Earlier versions | No |

## Reporting a vulnerability

Do not publish a suspected vulnerability in a public issue when it could expose credentials, command injection, sensitive network data, or a privilege-escalation path.

Use the repository's private GitHub security advisory feature when enabled. Otherwise, contact the maintainer, Nicolas Lermé, at <nicolas.lerme@gmail.com>. Include:

- the affected version;
- the operating system and Bash/Python versions;
- a minimal reproduction procedure;
- the expected and observed behavior;
- any relevant logs with secrets, addresses, host names, and device data removed.

## Operational security guidance

- Review the script before running it with elevated router or workstation privileges.
- Keep SSH host-key verification enabled.
- Prefer SSH keys protected by an agent or passphrase for repeatable automation.
- Disable SRM SSH access when it is not required.
- Treat generated CSV, HTML, and PDF files as sensitive network inventory.
- Never commit generated reports, passwords, private keys, router backups, or temporary files.
- Approve dependency installation only after reviewing the displayed package-manager command.
- Use a dedicated, minimally privileged account when SRM permissions permit it.

## Scope

Security reports concerning OpenSSH, Python, WeasyPrint, operating system package managers, or Synology SRM itself should also be reported to the relevant upstream project or vendor. This repository is responsible for defects in its own scripts, parsing logic, templates, and workflow.
