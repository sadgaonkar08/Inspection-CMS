"""Shared extraction helpers for ISI (Inspection Services, Inc.) lab reports."""

import re
from datetime import datetime

LAB_NAME = "ISI"
LAB_SIGNATURE = "INSPECTION SERVICES, INC."


def is_isi_report(text: str) -> bool:
    return LAB_SIGNATURE.lower() in text.lower()


def parse_us_date(s: str):
    """Parse '04/09/2026' or '03/12/26' -> '2026-04-09'."""
    if not s:
        return None
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
    if s is None or s == "":
        return None
    try:
        return float(str(s).replace(",", "").strip())
    except (ValueError, TypeError):
        return None


def to_int(s):
    v = to_float(s)
    return int(v) if v is not None else None


def clean(s):
    if s is None:
        return None
    s = str(s).strip()
    return s if s else None
