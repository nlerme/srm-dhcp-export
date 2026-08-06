#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Nicolas Lermé <nicolas.lerme@gmail.com>
# SPDX-License-Identifier: LGPL-3.0-only
# Integration and failure-path tests for srm-dhcp-export.

set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sde-tests.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SCRIPT="$ROOT/srm-dhcp-export.sh"
FAKE_PATH="$ROOT/tests/fakes:$PATH"
FIXTURE="$ROOT/tests/fixtures/dhcpd.conf"
EXPECTED_VERSION="$(cat "$ROOT/VERSION")"

fail() {
    printf 'Test failure: %s\n' "$1" >&2
    exit 1
}

expect_failure() {
    local expected_text="$1"
    local log_file="$2"
    shift 2

    if "$@" >"$log_file" 2>&1; then
        fail "Command unexpectedly succeeded: $*"
    fi
    grep -Fq "$expected_text" "$log_file" || {
        cat "$log_file" >&2
        fail "Expected error text was not found: $expected_text"
    }
}

run_fake_export() {
    local mode="$1"
    local ssh_log="$2"
    shift 2

    PATH="$FAKE_PATH" \
    SRM_DHCP_TEST_FIXTURE="$FIXTURE" \
    SRM_DHCP_TEST_MODE="$mode" \
    SRM_DHCP_TEST_LOG="$ssh_log" \
    "$SCRIPT" "$@"
}

printf 'Running shell syntax, help, version, and dependency checks...\n'
bash -n "$SCRIPT" "$ROOT/tests/run.sh" "$ROOT/tests/fakes/ssh"
[[ "$("$SCRIPT" --version)" == "srm-dhcp-export ${EXPECTED_VERSION}" ]]
"$SCRIPT" --help >/dev/null
PATH="$FAKE_PATH" "$SCRIPT" --check-dependencies >/dev/null

printf 'Running Python syntax checks...\n'
python3 -m py_compile "$ROOT/lib/process_reservations.py" "$ROOT/lib/render_pdf.py"

printf 'Testing reservation parsing and report generation...\n'
STATS="$(python3 "$ROOT/lib/process_reservations.py" \
    --input "$FIXTURE" \
    --csv "$TMP_DIR/direct.csv" \
    --html "$TMP_DIR/direct.html" \
    --template "$ROOT/templates/report.html" \
    --css "$ROOT/styles/report.css" \
    --source "192.168.0.1" \
    --version "$EXPECTED_VERSION")"

[[ "$STATS" == "4|1|1|1" ]] || fail "Unexpected parser statistics: $STATS"
grep -q 'AA:BB:CC:DD:EE:FF;192.168.1.20;laptop' "$TMP_DIR/direct.csv"
grep -q 'Synology DHCP Reservation Report' "$TMP_DIR/direct.html"
grep -q '192.168.0.1' "$TMP_DIR/direct.html"

printf 'Testing PDF rendering...\n'
python3 "$ROOT/lib/render_pdf.py" \
    --html "$TMP_DIR/direct.html" \
    --css "$ROOT/styles/report.css" \
    --output "$TMP_DIR/direct.pdf"
[[ "$(LC_ALL=C head -c 5 "$TMP_DIR/direct.pdf")" == "%PDF-" ]]

printf 'Testing successful explicit and default-host execution paths...\n'
SUCCESS_LOG="$TMP_DIR/success-ssh.log"
run_fake_export success "$SUCCESS_LOG" \
    --host "192.168.0.1" \
    --port "22" \
    --user "root" \
    --output "$TMP_DIR/integration.pdf" \
    --force \
    --non-interactive >/dev/null

[[ -s "$TMP_DIR/integration.csv" ]]
[[ -s "$TMP_DIR/integration.pdf" ]]
[[ ! -e "$TMP_DIR/integration.html" ]]
[[ "$(LC_ALL=C head -c 5 "$TMP_DIR/integration.pdf")" == "%PDF-" ]]
grep -Fq "Remote reservation list is not readable" "$SUCCESS_LOG"
grep -Fq "rm -f '/tmp/srm_dhcp_export_" "$SUCCESS_LOG"
grep -Fq -- "-O exit" "$SUCCESS_LOG"

DEFAULT_LOG="$TMP_DIR/default-ssh.log"
run_fake_export success "$DEFAULT_LOG" \
    --output "$TMP_DIR/default-host.pdf" \
    --keep-html \
    --force \
    --non-interactive >/dev/null
[[ -s "$TMP_DIR/default-host.html" ]]
grep -q '192.168.0.1' "$TMP_DIR/default-host.html"

INTERACTIVE_LOG="$TMP_DIR/interactive-ssh.log"
printf '\n\n\n%s\n' "$TMP_DIR/interactive.pdf" | \
    PATH="$FAKE_PATH" \
    SRM_DHCP_TEST_FIXTURE="$FIXTURE" \
    SRM_DHCP_TEST_MODE=success \
    SRM_DHCP_TEST_LOG="$INTERACTIVE_LOG" \
    "$SCRIPT" --force >/dev/null
[[ -s "$TMP_DIR/interactive.csv" ]]
[[ -s "$TMP_DIR/interactive.pdf" ]]
grep -Fq 'root@192.168.0.1' "$INTERACTIVE_LOG"

printf 'Testing input-validation and overwrite-protection paths...\n'
expect_failure "Invalid --host value." "$TMP_DIR/invalid-host.log" \
    env PATH="$FAKE_PATH" "$SCRIPT" --host 'bad@host' --non-interactive
expect_failure "Invalid --port value." "$TMP_DIR/invalid-port.log" \
    env PATH="$FAKE_PATH" "$SCRIPT" --port '70000' --non-interactive
expect_failure "Invalid --user value." "$TMP_DIR/invalid-user.log" \
    env PATH="$FAKE_PATH" "$SCRIPT" --user 'bad user' --non-interactive
: > "$TMP_DIR/existing.pdf"
expect_failure "Use --force to overwrite existing files in non-interactive mode." "$TMP_DIR/existing.log" \
    env PATH="$FAKE_PATH" "$SCRIPT" --output "$TMP_DIR/existing.pdf" --non-interactive

printf 'Testing SSH connection, remote export, and download failure paths...\n'
expect_failure "SSH authentication failed." "$TMP_DIR/connection-failure.log" \
    run_fake_export connection-failure "$TMP_DIR/connection-failure-ssh.log" \
        --output "$TMP_DIR/connection-failure.pdf" --force --non-interactive
printf '  Connection failure path passed.\n'

expect_failure "Unable to create the remote list." "$TMP_DIR/export-failure.log" \
    run_fake_export export-failure "$TMP_DIR/export-failure-ssh.log" \
        --output "$TMP_DIR/export-failure.pdf" --force --non-interactive
grep -Fq -- "-O exit" "$TMP_DIR/export-failure-ssh.log"
printf '  Remote export failure path passed.\n'

expect_failure "The reservation list download over SSH failed." "$TMP_DIR/download-failure.log" \
    run_fake_export download-failure "$TMP_DIR/download-failure-ssh.log" \
        --output "$TMP_DIR/download-failure.pdf" --force --non-interactive
grep -Fq "rm -f '/tmp/srm_dhcp_export_" "$TMP_DIR/download-failure-ssh.log"
grep -Fq -- "-O exit" "$TMP_DIR/download-failure-ssh.log"
[[ ! -e "$TMP_DIR/download-failure.pdf" ]]
printf '  Download failure path passed.\n'

expect_failure "The downloaded reservation list is empty." "$TMP_DIR/empty-download.log" \
    run_fake_export empty-download "$TMP_DIR/empty-download-ssh.log" \
        --output "$TMP_DIR/empty-download.pdf" --force --non-interactive
grep -Fq "rm -f '/tmp/srm_dhcp_export_" "$TMP_DIR/empty-download-ssh.log"
grep -Fq -- "-O exit" "$TMP_DIR/empty-download-ssh.log"
[[ ! -e "$TMP_DIR/empty-download.pdf" ]]
printf '  Empty download path passed.\n'

printf 'All tests passed.\n'
