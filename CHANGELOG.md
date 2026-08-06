# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2026-08-06

### Fixed

- Replaced the `scp` download with an SSH-streamed transfer to support older SRM SSH servers that do not provide an SFTP subsystem.
- Added success, validation, connection, export, download, empty-transfer, overwrite, and cleanup execution-path tests.

### Changed

- Changed the default router address from `192.168.1.1` to `192.168.0.1`.
- Added a linked table of contents to the README, moved router preparation and dependency behavior before quick start, and removed the installation section.

## [1.0.1] - 2026-08-06

### Changed

- Added Nicolas Lermé (`nicolas.lerme@gmail.com`) as the author and maintainer throughout the bundle.

## [1.0.0] - 2026-08-06

### Added

- Interactive SSH export of Synology SRM DHCP reservations.
- Automatic validation and optional installation of runtime dependencies.
- CSV normalization with IP sorting, duplicate removal, and incomplete-entry warnings.
- HTML report template and customizable CSS theme.
- WeasyPrint PDF generation with A4 landscape layout and repeated table headers.
- Secure local and remote temporary-file cleanup.
- Non-interactive command-line options.
- Tests, GitHub Actions workflow, contribution guidance, and security documentation.
