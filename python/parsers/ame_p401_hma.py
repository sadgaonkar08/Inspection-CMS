"""AME — P-401 HMA gyratory mix test results.

One row per sublot. Each sublot block in the PDF looks like:

    TS2-SL1 Test Date: 4/15/26 @ 74T (Time in Oven: 2 hrs)
    ASTM D2726, Bulk Specific Gravity 2.396 2.394 2.397 Avg: 2.396
    ASTM D2041, Rice Density 2.463 2.469 Avg: 2.466
    ASTM D3203, Air Voids*, % 2.83 2.90 2.80 Avg: 2.84

A project-requirement line appears once per report:
    *Project Requirement: Air Voids 2.5% to 4.5%.
"""

import re

from . import ame_common

EXPECTED_FIELDS = [
    "sublot_number",
    "test_date",
    "tonnage_point_tons",
    "time_in_oven_hrs",
    "gyrations",
    "gmb_samples",
    "gmb_avg",
    "gmm_samples",
    "gmm_avg",
    "air_voids_samples",
    "air_voids_avg",
    "air_voids_min_pct",
    "air_voids_max_pct",
    "result",
]

SUBLOT_HEADER_RE = re.compile(
    r"(?P<sublot>[A-Z0-9]+-SL\d+)\s+Test Date:\s*(?P<date>\d{1,2}/\d{1,2}/\d{2,4})"
    r"\s*@\s*(?P<tons>\d+)T"
    r"\s*\(Time in Oven:\s*(?P<oven>\d+)\s*hrs?\)"
)

GMB_RE = re.compile(
    r"ASTM\s+D2726.*?Bulk Specific Gravity\s+([\d.\s]+?)Avg:\s*([\d.]+)",
    re.IGNORECASE,
)
GMM_RE = re.compile(
    r"ASTM\s+D2041.*?Rice Density\s+([\d.\s]+?)Avg:\s*([\d.]+)",
    re.IGNORECASE,
)
AIR_VOIDS_RE = re.compile(
    r"ASTM\s+D3203.*?Air Voids[^\n]*?%\s+([\d.\s]+?)Avg:\s*([\d.]+)",
    re.IGNORECASE,
)
AIR_VOIDS_REQ_RE = re.compile(
    r"Project Requirement[s]?:\s*Air Voids\s+([\d.]+)\s*%\s*to\s*([\d.]+)\s*%",
    re.IGNORECASE,
)
GYRATIONS_RE = re.compile(r"(\d+)\s+gyrations", re.IGNORECASE)


def parse(text: str) -> dict:
    header = ame_common.parse_header(text)
    errors = []

    req_min, req_max = _parse_air_voids_requirement(text)
    if req_min is None or req_max is None:
        errors.append("missing_air_voids_requirement")

    gyrations_m = GYRATIONS_RE.search(text)
    gyrations = ame_common.to_int(gyrations_m.group(1)) if gyrations_m else None
    if gyrations is None:
        errors.append("missing_gyrations")

    blocks = _split_sublot_blocks(text)
    if not blocks:
        errors.append("no_sublot_blocks_found")

    rows = []
    for sublot_header, body in blocks:
        row, row_errors = _parse_sublot(sublot_header, body, req_min, req_max, gyrations)
        rows.append(row)
        errors.extend(row_errors)

    return {"header": header, "rows": rows, "errors": errors}


def _parse_air_voids_requirement(text: str):
    m = AIR_VOIDS_REQ_RE.search(text)
    if not m:
        return None, None
    return ame_common.to_float(m.group(1)), ame_common.to_float(m.group(2))


def _split_sublot_blocks(text: str):
    """Return [(header_match, body_text), ...] for each sublot in document order."""
    matches = list(SUBLOT_HEADER_RE.finditer(text))
    blocks = []
    for i, m in enumerate(matches):
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        blocks.append((m, text[start:end]))
    return blocks


def _parse_sublot(header_match, body, req_min, req_max, gyrations):
    errors = []
    sublot_tag = f"@{header_match.group('sublot')}"

    gmb_samples, gmb_avg = _parse_samples(GMB_RE, body)
    if gmb_avg is None:
        errors.append(f"missing_gmb{sublot_tag}")

    gmm_samples, gmm_avg = _parse_samples(GMM_RE, body)
    if gmm_avg is None:
        errors.append(f"missing_gmm{sublot_tag}")

    air_samples, air_avg = _parse_samples(AIR_VOIDS_RE, body)
    if air_avg is None:
        errors.append(f"missing_air_voids{sublot_tag}")

    result = _compute_result(air_avg, req_min, req_max)

    return (
        {
            "sublot_number": header_match.group("sublot"),
            "test_date": ame_common.parse_short_date(header_match.group("date")),
            "tonnage_point_tons": ame_common.to_int(header_match.group("tons")),
            "time_in_oven_hrs": ame_common.to_int(header_match.group("oven")),
            "gyrations": gyrations,
            "gmb_samples": gmb_samples,
            "gmb_avg": gmb_avg,
            "gmm_samples": gmm_samples,
            "gmm_avg": gmm_avg,
            "air_voids_samples": air_samples,
            "air_voids_avg": air_avg,
            "air_voids_min_pct": req_min,
            "air_voids_max_pct": req_max,
            "result": result,
        },
        errors,
    )


def _parse_samples(pattern: re.Pattern, text: str):
    m = pattern.search(text)
    if not m:
        return [], None
    samples = [ame_common.to_float(x) for x in m.group(1).split()]
    samples = [s for s in samples if s is not None]
    avg = ame_common.to_float(m.group(2))
    return samples, avg


def _compute_result(air_avg, req_min, req_max):
    if air_avg is None or req_min is None or req_max is None:
        return None
    return "pass" if req_min <= air_avg <= req_max else "fail"
