#!/usr/bin/env python3
"""Quick CLI harness for iterating on lab-report parsers.

Usage:
    python test_extract.py <pdf_path> <P-401|P-403>

Thin wrapper around extract_lab_report.run() that prints a summary line plus
the full JSON payload. Used during parser development; not called from Rails.
"""

import sys

from extract_lab_report import run

USAGE = "usage: test_extract.py <pdf_path> <P-401|P-403>"


def main() -> int:
    if len(sys.argv) != 3:
        print(USAGE, file=sys.stderr)
        return 2

    pdf_path, spec = sys.argv[1], sys.argv[2]
    payload, exit_code = run(pdf_path, spec)

    rows = payload.get("rows", [])
    errors = payload.get("errors", [])
    print(f"spec={spec} parser={payload.get('parser_used')} rows={len(rows)} errors={len(errors)} exit={exit_code}")
    if errors:
        print("errors:")
        for e in errors:
            print(f"  - {e}")

    import json as _json
    print(_json.dumps(payload, indent=2, default=str))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
