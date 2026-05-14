#!/usr/bin/env python3
"""Lab test PDF extractor (dispatcher).

Reads an asphalt lab test PDF, detects the lab, dispatches to the matching
parser, and emits a single JSON object on stdout.

Usage:
    python extract_lab_report.py --pdf <path> --spec P-401|P-403

Exit codes:
    0  success (including partial extraction with listed errors)
    1  unexpected exception (traceback on stderr)
    2  PDF has no extractable text (scanned image)
    3  unknown lab (no matching parser)
    4  bad CLI arguments
"""

import argparse
import json
import sys
import traceback

import pdfplumber

from parsers import (
    ame_common,
    ame_p401_hma,
    ame_p403_cores,
    isi_common,
    isi_p610_concrete,
)

SPEC_CODES = ("P-401", "P-403", "P-610")

# Spec -> list of (detector, parser_module, parser_name). First matching detector wins.
# P-401 may arrive as either an HMA mix report or a cores report; the cores detector
# is checked first so cores PDFs route to the cores parser regardless of spec code.
DISPATCH = {
    "P-401": [
        (ame_common.is_cores_report, ame_p403_cores, "ame_p403_cores"),
        (ame_common.is_ame_report, ame_p401_hma, "ame_p401_hma"),
    ],
    "P-403": [(ame_common.is_ame_report, ame_p403_cores, "ame_p403_cores")],
    "P-610": [(isi_common.is_isi_report, isi_p610_concrete, "isi_p610_concrete")],
}


def extract_text(pdf_path: str) -> str:
    parts = []
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            t = page.extract_text() or ""
            if t:
                parts.append(t)
    return "\n".join(parts)


def run(pdf_path: str, spec_code: str) -> tuple[dict, int]:
    text = extract_text(pdf_path)
    if not text.strip():
        return (
            {"spec_code": spec_code, "errors": ["no_text_scanned"], "rows": []},
            2,
        )

    dispatch = DISPATCH.get(spec_code)
    if dispatch is None:
        return (
            {"spec_code": spec_code, "errors": [f"unsupported_spec:{spec_code}"], "rows": []},
            4,
        )

    for detector, module, parser_name in dispatch:
        if detector(text):
            result = module.parse(text)
            return (
                {
                    "spec_code": spec_code,
                    "parser_used": parser_name,
                    "header": result.get("header", {}),
                    "rows": result.get("rows", []),
                    "errors": result.get("errors", []),
                    "row_count": len(result.get("rows", [])),
                },
                0,
            )

    return (
        {"spec_code": spec_code, "errors": ["unknown_lab"], "rows": []},
        3,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract structured data from a lab test PDF.")
    parser.add_argument("--pdf", required=True, help="Path to the PDF file.")
    parser.add_argument("--spec", required=True, choices=SPEC_CODES, help="Spec code.")
    args = parser.parse_args()

    try:
        payload, exit_code = run(args.pdf, args.spec)
    except Exception:
        traceback.print_exc()
        return 1

    json.dump(payload, sys.stdout, indent=2, default=str)
    sys.stdout.write("\n")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
