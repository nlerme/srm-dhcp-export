#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Nicolas Lermé <nicolas.lerme@gmail.com>
# SPDX-License-Identifier: LGPL-3.0-only
# Lightweight integration tests for srm-dhcp-export.

set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sde-tests.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

printf 'Running shell syntax and version checks...\n'
bash -n "$ROOT/srm-dhcp-export.sh"
EXPECTED_VERSION="$(cat "$ROOT/VERSION")"
[[ "$("$ROOT/srm-dhcp-export.sh" --version)" == "srm-dhcp-export ${EXPECTED_VERSION}" ]]

printf 'Running Python syntax checks...\n'
python3 -m py_compile "$ROOT/lib/process_reservations.py" "$ROOT/lib/render_pdf.py"

printf 'Testing reservation parsing and report generation...\n'
STATS="$(python3 "$ROOT/lib/process_reservations.py" \
    --input "$ROOT/tests/fixtures/dhcpd.conf" \
    --csv "$TMP_DIR/direct.csv" \
    --html "$TMP_DIR/direct.html" \
    --template "$ROOT/templates/report.html" \
    --css "$ROOT/styles/report.css" \
    --source "192.168.1.1" \
    --version "$EXPECTED_VERSION")"

[[ "$STATS" == "4|1|1|1" ]] || {
    printf 'Unexpected parser statistics: %s\n' "$STATS" >&2
    exit 1
}

grep -q 'AA:BB:CC:DD:EE:FF;192.168.1.20;laptop' "$TMP_DIR/direct.csv"
grep -q 'Synology DHCP Reservation Report' "$TMP_DIR/direct.html"

printf 'Testing PDF rendering...\n'
python3 "$ROOT/lib/render_pdf.py" \
    --html "$TMP_DIR/direct.html" \
    --css "$ROOT/styles/report.css" \
    --output "$TMP_DIR/direct.pdf"
[[ "$(LC_ALL=C head -c 5 "$TMP_DIR/direct.pdf")" == "%PDF-" ]]

printf 'Testing the complete interactive script in non-interactive mode...\n'
PATH="$ROOT/tests/fakes:$PATH" \
SRM_DHCP_TEST_FIXTURE="$ROOT/tests/fixtures/dhcpd.conf" \
"$ROOT/srm-dhcp-export.sh" \
    --host "192.168.1.1" \
    --port "22" \
    --user "root" \
    --output "$TMP_DIR/integration.pdf" \
    --keep-html \
    --force \
    --non-interactive

[[ -s "$TMP_DIR/integration.csv" ]]
[[ -s "$TMP_DIR/integration.html" ]]
[[ "$(LC_ALL=C head -c 5 "$TMP_DIR/integration.pdf")" == "%PDF-" ]]

printf 'All tests passed.\n'
