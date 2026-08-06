#!/usr/bin/env python3
"""Render a styled HTML report to PDF with WeasyPrint."""

# SPDX-FileCopyrightText: 2026 Nicolas Lermé <nicolas.lerme@gmail.com>
# SPDX-License-Identifier: LGPL-3.0-only

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--html", required=True, type=Path, help="Input HTML report")
    parser.add_argument("--css", required=True, type=Path, help="Input CSS stylesheet")
    parser.add_argument("--output", required=True, type=Path, help="Output PDF file")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    for required_path in (args.html, args.css):
        if not required_path.is_file():
            print(f"Required file not found: {required_path}", file=sys.stderr)
            return 2

    try:
        from weasyprint import CSS, HTML
    except ImportError:
        print(
            "WeasyPrint is not installed for the selected Python interpreter.",
            file=sys.stderr,
        )
        return 3

    try:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        HTML(
            filename=str(args.html.resolve()),
            base_url=str(args.html.resolve().parent),
        ).write_pdf(
            str(args.output),
            stylesheets=[CSS(filename=str(args.css.resolve()))],
        )
    except Exception as exc:  # WeasyPrint exposes backend-specific exceptions.
        print(f"WeasyPrint failed: {exc}", file=sys.stderr)
        return 4

    try:
        header = args.output.read_bytes()[:5]
        if header != b"%PDF-":
            raise ValueError("output does not contain a PDF header")
    except (OSError, ValueError) as exc:
        print(f"Invalid PDF output: {exc}", file=sys.stderr)
        return 5

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
