"""Shared extraction helpers for AME (Applied Materials & Engineering) lab reports.

Both P-401 HMA and P-403 core reports use an identical letterhead block;
this module extracts that header and exposes small numeric helpers.
"""

import re
from datetime import datetime

LAB_NAME = "AME"
LAB_SIGNATURE = "Applied Materials & Engineering"

MONTHS = {
    "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
    "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
}


def is_ame_report(text: str) -> bool:
    return LAB_SIGNATURE.lower() in text.lower()


def is_cores_report(text: str) -> bool:
    """True for AME core/compaction reports (used for both P-403 and P-401 cores).

    Cores reports always carry a 'Core ID' header row and a 'Compaction*, %' row;
    HMA mix reports have neither. Both markers are required so a stray mention in
    body prose doesn't trigger a false positive.
    """
    if not is_ame_report(text):
        return False
    has_core_id = re.search(r"^\s*Core\s+ID\s+", text, re.MULTILINE) is not None
    has_compaction = re.search(r"Compaction\*?,?\s*%", text) is not None
    return has_core_id and has_compaction


def parse_header(text: str) -> dict:
    """Extract the letterhead fields common to AME P-401 and P-403 reports.

    Returns a dict with string values (or None) for:
      lab_name, report_date, project_number, project_subject, plant, mix_number
    """
    return {
        "lab_name": LAB_NAME,
        "report_date": _parse_letter_date(text),
        "project_number": _match(r"Project\s+Number\s+([A-Za-z0-9\-]+)", text),
        "project_subject": _parse_subject(text),
        "plant": _parse_plant(text),
        "mix_number": _match(r"Mix\s+No\.?\s+(\d+)", text),
    }


def _parse_letter_date(text: str):
    # AME letters lead with a full date line like "April 16, 2026"
    m = re.search(
        r"^\s*(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),\s*(\d{4})",
        text,
        re.IGNORECASE | re.MULTILINE,
    )
    if not m:
        return None
    month = MONTHS[m.group(1).lower()]
    return f"{int(m.group(3)):04d}-{month:02d}-{int(m.group(2)):02d}"


def _parse_subject(text: str):
    # "Subject: ..." sometimes wraps to the next line in pdfplumber output.
    m = re.search(r"Subject:\s*(.+)", text)
    if not m:
        return None
    subject = m.group(1).strip()
    # If the next non-empty line looks like a continuation (not a new labeled section), append it.
    lines = text.splitlines()
    for i, ln in enumerate(lines):
        if ln.strip().startswith("Subject:"):
            if i + 1 < len(lines):
                nxt = lines[i + 1].strip()
                if nxt and ":" not in nxt and not nxt.startswith("Dear"):
                    subject = f"{subject} {nxt}"
            break
    return subject


def _parse_plant(text: str):
    # e.g. "Granite – Santa Clara Plant" or "Granite - Pleasanton Plant"
    m = re.search(r"(Granite\s*[\u2013\-]\s*[A-Za-z ]+Plant)", text)
    return m.group(1).strip() if m else None


def _match(pattern: str, text: str, flags: int = 0):
    m = re.search(pattern, text, flags)
    return m.group(1).strip() if m else None


def parse_short_date(s: str):
    """Parse AME's short test-date format like '4/15/26' -> '2026-04-15'."""
    m = re.match(r"(\d{1,2})/(\d{1,2})/(\d{2,4})", s.strip())
    if not m:
        return None
    mo, day, yr = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if yr < 100:
        yr += 2000
    try:
        return datetime(yr, mo, day).strftime("%Y-%m-%d")
    except ValueError:
        return None


def to_float(s):
    if s is None:
        return None
    try:
        return float(str(s).replace(",", "").strip())
    except (ValueError, TypeError):
        return None


def to_int(s):
    v = to_float(s)
    return int(v) if v is not None else None
