# srm-dhcp-export

![Version](https://img.shields.io/badge/version-1.0.1-0A7BBB)
![License](https://img.shields.io/badge/license-LGPL--3.0--only-2E8B57)
![Bash](https://img.shields.io/badge/Bash-3.2%2B-4EAA25?logo=gnubash&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.8%2B-3776AB?logo=python&logoColor=white)
![OpenSSH](https://img.shields.io/badge/OpenSSH-client-5E5E5E?logo=openssh&logoColor=white)
![WeasyPrint](https://img.shields.io/badge/WeasyPrint-52.5%2B-1F6FEB)
![HTML5](https://img.shields.io/badge/HTML5-report-E34F26?logo=html5&logoColor=white)
![CSS3](https://img.shields.io/badge/CSS3-theme-1572B6?logo=css3&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-6C757D)

## Description

`srm-dhcp-export` is an interactive Bash bundle that connects to a Synology router running SRM, reads static DHCP reservations from `/etc/dhcpd/dhcpd.conf`, downloads a temporary raw list, normalizes the data, and creates:

- a semicolon-delimited UTF-8 CSV file;
- a styled HTML report when `--keep-html` is enabled;
- an A4 landscape PDF report rendered from HTML and CSS.

The default target is suitable for a Synology RT1900ac using the SRM 1.2 configuration layout confirmed by the project use case. The configuration path can be changed in `srm-dhcp-export.sh` if another SRM release stores DHCP data elsewhere.

## Bundle contents

```text
srm-dhcp-export-1.0.0/
├── srm-dhcp-export.sh          Main interactive exporter
├── lib/
│   ├── process_reservations.py DHCP parser and CSV/HTML generator
│   └── render_pdf.py           WeasyPrint PDF renderer
├── styles/report.css           Customizable PDF/HTML theme
├── templates/report.html       Report structure
├── tests/                      Fixtures, test doubles, and integration tests
├── .github/workflows/ci.yml    GitHub Actions checks
├── README.md
├── SECURITY.md
├── CONTRIBUTING.md
├── CHANGELOG.md
├── AUTHORS.md
├── LICENSE                     GNU LGPL version 3 terms
├── COPYING                     GNU GPL version 3 terms incorporated by LGPLv3
├── MANIFEST.sha256             SHA-256 checksums for bundled files
└── VERSION
```

## Features

- Interactive prompts with validation, numbered steps, spacing, and terminal colors.
- Command-line options for scripted or non-interactive execution.
- Dependency detection at startup.
- Explicit confirmation before installing missing dependencies.
- Package-manager support for APT, DNF, YUM, Pacman, Zypper, APK, and Homebrew.
- Reused SSH connection, so password authentication is normally requested once.
- IPv4, IPv6, and DNS host input validation.
- Sorting by IP address.
- Duplicate removal and incomplete-entry warnings.
- UTF-8 CSV output with a byte-order mark for spreadsheet compatibility.
- CSS-driven PDF layout with repeating table headers and page counters.
- Automatic local and remote temporary-file cleanup.
- Strict output permissions through `umask 077` and `chmod 600` where supported.

## Dependencies

### Runtime dependencies

| Dependency | Purpose |
|---|---|
| Bash 3.2 or later | Interactive orchestration and SSH workflow |
| OpenSSH client (`ssh`, `scp`) | Router connection and file transfer |
| Python 3.8 or later | DHCP parsing, validation, and report generation |
| WeasyPrint 52.5 or later | HTML/CSS to PDF rendering |
| Standard core utilities | Temporary files, file moves, permissions, line counting |

The script checks these requirements during step 1. When dependencies are missing, it prints the complete list, shows the proposed package-manager command, and asks whether it should run that command.

### Manual installation examples

Debian or Ubuntu:

```bash
sudo apt-get update
sudo apt-get install openssh-client python3 weasyprint
```

Fedora:

```bash
sudo dnf install openssh-clients python3 weasyprint
```

Arch Linux:

```bash
sudo pacman -S --needed openssh python python-weasyprint
```

macOS with Homebrew:

```bash
brew install openssh python weasyprint
```

WeasyPrint may require Pango and related native libraries when installed with `pip`. Prefer the operating system package or Homebrew formula where available. See the official [WeasyPrint installation documentation](https://doc.courtbouillon.org/weasyprint/stable/first_steps.html) for platform-specific details.

A Python dependency declaration is also provided:

```bash
python3 -m pip install -r requirements.txt
```

This method may still require native packages supplied by the operating system.

## Installation

Download or clone the repository, then make the main script executable:

```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/srm-dhcp-export.git
cd srm-dhcp-export
chmod +x srm-dhcp-export.sh
```

Replace `YOUR_GITHUB_USERNAME` after publishing the repository.

## Quick start

Run the interactive exporter:

```bash
./srm-dhcp-export.sh
```

Default values:

```text
Router:     192.168.1.1
SSH port:   22
SSH user:   root
PDF output: device_list.pdf
Stylesheet: styles/report.css
```

The script creates `device_list.pdf` and `device_list.csv` in the current directory. Add `--keep-html` to retain `device_list.html`.

## Command-line usage

```text
./srm-dhcp-export.sh [options]

--host HOST              Router IP address or DNS name
--port PORT              SSH port
--user USER              SSH user
--output FILE            Output PDF path
--css FILE               Custom PDF stylesheet
--keep-html              Keep the generated HTML report
--force                  Overwrite existing reports without asking
--non-interactive        Use supplied values/defaults without prompts
--install-dependencies   Install missing dependencies without confirmation
--check-dependencies     Check dependencies and exit
--version                Print the version and exit
-h, --help               Show help
```

Example:

```bash
./srm-dhcp-export.sh \
  --host 192.168.1.1 \
  --port 22 \
  --user root \
  --output reports/home-network.pdf \
  --keep-html
```

For unattended execution, provide all required values and protect authentication with an SSH key:

```bash
./srm-dhcp-export.sh \
  --host router.example.net \
  --user root \
  --output reports/device-list.pdf \
  --non-interactive \
  --force
```

## Router preparation

1. Enable SSH in the SRM control panel.
2. Confirm that the selected account can authenticate through SSH.
3. Confirm that the account can read `/etc/dhcpd/dhcpd.conf`.
4. Run the exporter from a trusted workstation on a trusted network.
5. Disable SSH again after use when it is not otherwise required.

Authentication behavior varies by SRM version and account configuration. On older SRM releases, root SSH authentication may use the password of the built-in administrator account. Do not store that password in this repository or in shell scripts.

## Dependency management behavior

The script never installs packages silently during normal interactive use. It performs the following sequence:

1. Detect missing commands and Python modules.
2. Print each missing dependency.
3. Detect a supported package manager.
4. Display the exact installation command.
5. Ask for confirmation.
6. Use `sudo` only when the package manager requires elevated privileges.
7. Run the dependency check again after installation.

Use `--install-dependencies` only when automatic installation is explicitly intended. In non-interactive mode, missing dependencies cause an error unless that flag is also supplied.

## Output files

For an output path named `reports/network.pdf`, the bundle produces:

```text
reports/network.pdf
reports/network.csv
reports/network.html   # only with --keep-html
```

The CSV columns are:

```text
MAC address;IP address;Device name
```

The repository also includes `MANIFEST.sha256`, which records SHA-256 checksums for every bundled file except the manifest itself. Verify it from the repository root with:

```bash
sha256sum --check MANIFEST.sha256
```

Rows are sorted numerically by IP address. Exact duplicates are removed. Missing values remain visible in the PDF and HTML reports as `Not available`.

## Changing the PDF table style

The report appearance is controlled by [`styles/report.css`](styles/report.css). The main script passes this file to WeasyPrint when rendering the PDF.

The fastest customization method is to edit the custom properties at the top of the file:

```css
:root {
  --accent-color: #1565c0;
  --table-header-background: #1565c0;
  --table-header-text: #ffffff;
  --table-border-color: #c9d3df;
  --table-row-background: #ffffff;
  --table-stripe-background: #eef4fa;
  --table-font-size: 9.2pt;
  --table-cell-padding: 6px 8px;
}
```

Useful selectors:

| Selector | Controls |
|---|---|
| `.device-table` | Overall table sizing and layout |
| `.device-table thead th` | Header background, text, and typography |
| `.device-table tbody tr:nth-child(even) td` | Alternating row color |
| `.column-number`, `.column-mac`, `.column-ip`, `.column-name` | Column widths |
| `.mac-address`, `.ip-address` | Monospaced address formatting |
| `.report-header` | Report title area |
| `.metadata` | Source/date/version panel |
| `@page` | Paper size, margins, and page numbering |

To keep the original stylesheet unchanged, copy it and pass the copy at runtime:

```bash
cp styles/report.css styles/my-report.css
./srm-dhcp-export.sh --css styles/my-report.css
```

The HTML structure is stored in [`templates/report.html`](templates/report.html). Preserve markers such as `@@ROWS@@`, `@@SOURCE@@`, and `@@DEVICE_COUNT@@` when editing the template.

## Security considerations

- **Credentials:** the script does not read, capture, log, or store SSH passwords. OpenSSH handles authentication directly.
- **Host verification:** SSH host-key verification is not disabled. Review any first-connection fingerprint carefully. A changed fingerprint must be investigated rather than bypassed.
- **Privilege:** the default SSH user is `root` because the SRM configuration file may require elevated read access. Use a less-privileged account when it can read the file safely.
- **Remote changes:** the exporter only reads the DHCP configuration and creates a short-lived file under `/tmp`. It does not modify DHCP reservations.
- **Temporary data:** remote and local temporary files are deleted through an exit trap, including interrupted runs where cleanup remains possible.
- **Output sensitivity:** MAC addresses, IP addresses, and device names expose a local network inventory. Store reports securely and do not publish generated reports in the GitHub repository.
- **File permissions:** outputs are created with owner-only permissions where the platform supports POSIX permissions.
- **Package installation:** inspect the proposed installation command before approving it. Package-manager operations may require administrator privileges.
- **Repository hygiene:** never commit passwords, private keys, exported CSV/PDF/HTML reports, router backups, or known-host exceptions.

See [SECURITY.md](SECURITY.md) for vulnerability reporting and operational guidance.

## Testing

Run the included test suite:

```bash
./tests/run.sh
```

The tests cover:

- Bash syntax;
- Python syntax;
- DHCP line parsing;
- field-order normalization;
- duplicate and invalid-line handling;
- CSV and HTML generation;
- WeasyPrint PDF rendering;
- a complete exporter run with local SSH/SCP test doubles.

Run ShellCheck separately when installed:

```bash
shellcheck srm-dhcp-export.sh tests/run.sh tests/fakes/ssh tests/fakes/scp
```

The GitHub Actions workflow runs these checks on pushes and pull requests.

## Development

Common Make targets:

```bash
make check
make test
make package
```

`make package` uses `git archive`, so commit the files before creating a release archive.

## Troubleshooting

### `Permission denied, please try again`

The router accepted the TCP/SSH connection but rejected authentication. Verify the SSH user, the account status, the configured SSH port, and the password or SSH key permitted by the installed SRM version.

### `DHCP configuration is not readable`

The connected account cannot read `/etc/dhcpd/dhcpd.conf`, or the installed SRM version uses another location. Check the path manually over SSH and update `REMOTE_CONFIG` near the top of `srm-dhcp-export.sh` when necessary.

### `No DHCP reservations were found`

Confirm that SRM contains static reservations and that the configuration file includes lines beginning with `dhcp-host=`.

### WeasyPrint import or rendering error

Run:

```bash
./srm-dhcp-export.sh --check-dependencies
python3 -c 'import weasyprint; print(weasyprint.__version__)'
```

Install WeasyPrint and its native dependencies through the platform package manager when possible.

### The PDF styling is incorrect

Restore `styles/report.css`, test with the default theme, and validate custom CSS incrementally. Unsupported browser-specific CSS may be ignored by WeasyPrint.

## License

This project is licensed under the **GNU Lesser General Public License version 3 only** (`LGPL-3.0-only`). See [LICENSE](LICENSE).

LGPLv3 incorporates the GNU General Public License version 3 terms. A copy is included in [COPYING](COPYING).

Third-party dependencies remain under their respective licenses. WeasyPrint is not bundled into this repository; it is installed separately on the user system.

## Author

**Nicolas Lermé** (<nicolas.lerme@gmail.com>) is the project author and maintainer. See [AUTHORS.md](AUTHORS.md).

Contributions are welcome under the terms described in [CONTRIBUTING.md](CONTRIBUTING.md).
