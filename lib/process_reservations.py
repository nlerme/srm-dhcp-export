#!/usr/bin/env python3
"""Parse Synology SRM DHCP reservations and create CSV/HTML reports."""

# SPDX-FileCopyrightText: 2026 Nicolas Lermé <nicolas.lerme@gmail.com>
# SPDX-License-Identifier: LGPL-3.0-only

from __future__ import annotations

import argparse
import csv
import datetime as dt
import html
import ipaddress
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Set, Tuple

MAC_PATTERN = re.compile(r"^(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$")
LEASE_PATTERN = re.compile(r"^[0-9]+[smhdw]?$", re.IGNORECASE)
IGNORED_PREFIXES = ("set:", "tag:", "net:", "id:")
IGNORED_VALUES = {"ignore", "infinite", "*"}


@dataclass(frozen=True)
class Reservation:
    """Normalized DHCP reservation."""

    mac: str
    ip_address: str
    device_name: str


@dataclass(frozen=True)
class ParseStats:
    """Counters collected while parsing the source file."""

    exported: int
    incomplete: int
    invalid: int
    duplicates: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Raw DHCP reservation list")
    parser.add_argument("--csv", required=True, type=Path, help="Destination CSV file")
    parser.add_argument("--html", required=True, type=Path, help="Destination HTML file")
    parser.add_argument("--template", required=True, type=Path, help="HTML template")
    parser.add_argument("--css", required=True, type=Path, help="CSS file referenced by the HTML")
    parser.add_argument("--source", required=True, help="Router address shown in the report")
    parser.add_argument("--version", required=True, help="Bundle version shown in the report")
    return parser.parse_args()


def normalize_mac(value: str) -> str:
    return value.replace("-", ":").upper()


def normalize_ip(value: str) -> str:
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        return ""


def is_ignored_token(value: str) -> bool:
    lowered = value.casefold()
    return (
        not value
        or lowered in IGNORED_VALUES
        or lowered.startswith(IGNORED_PREFIXES)
        or LEASE_PATTERN.fullmatch(lowered) is not None
    )


def split_payload(payload: str) -> List[str]:
    """Split a dnsmasq-style comma list while respecting quoted values."""
    try:
        parsed = next(csv.reader([payload], skipinitialspace=True))
    except (csv.Error, StopIteration):
        parsed = payload.split(",")
    return [token.strip().strip("\"").strip("'") for token in parsed]


def extract_payload(raw_line: str) -> str:
    line = raw_line.strip()
    marker = "dhcp-host="
    if not line or marker not in line:
        return ""

    payload = line.split(marker, 1)[1].strip()
    if not payload:
        return ""

    # SRM-generated entries are normally unquoted. A trailing # comment is
    # stripped conservatively because # is not valid in the expected fields.
    return payload.split("#", 1)[0].strip()


def parse_reservations(lines: Iterable[str]) -> Tuple[List[Reservation], ParseStats]:
    reservations: List[Reservation] = []
    seen: Set[Tuple[str, str, str]] = set()
    invalid = 0
    incomplete = 0
    duplicates = 0

    for raw_line in lines:
        payload = extract_payload(raw_line)
        if not payload:
            continue

        tokens = split_payload(payload)
        mac = ""
        ip_address = ""

        for token in tokens:
            if not mac and MAC_PATTERN.fullmatch(token):
                mac = normalize_mac(token)
                continue
            if not ip_address:
                candidate_ip = normalize_ip(token)
                if candidate_ip:
                    ip_address = candidate_ip

        name_candidates: List[str] = []
        for token in tokens:
            if MAC_PATTERN.fullmatch(token):
                continue
            if normalize_ip(token):
                continue
            if is_ignored_token(token):
                continue
            name_candidates.append(token)

        device_name = name_candidates[0] if name_candidates else ""

        if not mac and not ip_address:
            invalid += 1
            continue

        if not mac or not ip_address or not device_name:
            incomplete += 1

        key = (mac, ip_address, device_name.casefold())
        if key in seen:
            duplicates += 1
            continue
        seen.add(key)

        reservations.append(
            Reservation(mac=mac, ip_address=ip_address, device_name=device_name)
        )

    def sort_key(item: Reservation) -> Tuple[object, ...]:
        try:
            address = ipaddress.ip_address(item.ip_address)
            return (0, address.version, int(address), item.device_name.casefold(), item.mac)
        except ValueError:
            return (1, 99, 0, item.device_name.casefold(), item.mac)

    reservations.sort(key=sort_key)
    stats = ParseStats(
        exported=len(reservations),
        incomplete=incomplete,
        invalid=invalid,
        duplicates=duplicates,
    )
    return reservations, stats


def write_csv(path: Path, reservations: List[Reservation]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as output:
        writer = csv.writer(output, delimiter=";", quoting=csv.QUOTE_MINIMAL)
        writer.writerow(["MAC address", "IP address", "Device name"])
        for reservation in reservations:
            writer.writerow(
                [reservation.mac, reservation.ip_address, reservation.device_name]
            )


def display_value(value: str) -> str:
    return html.escape(value, quote=True) if value else '<span class="missing">Not available</span>'


def build_rows(reservations: List[Reservation]) -> str:
    rows: List[str] = []
    for index, reservation in enumerate(reservations, start=1):
        rows.append(
            "\n".join(
                [
                    "        <tr>",
                    f'          <td class="row-number">{index}</td>',
                    f'          <td class="mac-address">{display_value(reservation.mac)}</td>',
                    f'          <td class="ip-address">{display_value(reservation.ip_address)}</td>',
                    f'          <td class="device-name">{display_value(reservation.device_name)}</td>',
                    "        </tr>",
                ]
            )
        )
    return "\n".join(rows)


def replace_markers(template: str, values: Dict[str, str]) -> str:
    output = template
    for marker, value in values.items():
        output = output.replace(f"@@{marker}@@", value)

    unresolved = sorted(set(re.findall(r"@@[A-Z0-9_]+@@", output)))
    if unresolved:
        raise ValueError(f"Unresolved template markers: {', '.join(unresolved)}")
    return output


def write_html(
    path: Path,
    template_path: Path,
    css_path: Path,
    reservations: List[Reservation],
    source: str,
    version: str,
) -> None:
    template = template_path.read_text(encoding="utf-8")
    generated = dt.datetime.now().astimezone()
    generated_human = generated.strftime("%Y-%m-%d %H:%M:%S %Z")
    generated_iso = generated.isoformat(timespec="seconds")

    values = {
        "TITLE": "Synology DHCP Reservation Report",
        "SOURCE": html.escape(source, quote=True),
        "GENERATED_HUMAN": html.escape(generated_human, quote=True),
        "GENERATED_ISO": html.escape(generated_iso, quote=True),
        "DEVICE_COUNT": str(len(reservations)),
        "ROWS": build_rows(reservations),
        "VERSION": html.escape(version, quote=True),
        "CSS_URI": html.escape(css_path.resolve().as_uri(), quote=True),
    }
    rendered = replace_markers(template, values)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(rendered, encoding="utf-8")


def main() -> int:
    args = parse_args()

    for required_path in (args.input, args.template, args.css):
        if not required_path.is_file():
            print(f"Required file not found: {required_path}", file=sys.stderr)
            return 2

    try:
        source_lines = args.input.read_text(encoding="utf-8", errors="replace").splitlines()
        reservations, stats = parse_reservations(source_lines)
        if not reservations:
            print("No usable DHCP reservations were found.", file=sys.stderr)
            return 3

        write_csv(args.csv, reservations)
        write_html(
            args.html,
            args.template,
            args.css,
            reservations,
            args.source,
            args.version,
        )
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"Report generation failed: {exc}", file=sys.stderr)
        return 4

    print(
        f"{stats.exported}|{stats.incomplete}|{stats.invalid}|{stats.duplicates}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
