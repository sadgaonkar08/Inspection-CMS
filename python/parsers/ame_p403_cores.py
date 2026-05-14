"""AME — in-place cores (density/compaction). Used for both P-403 and P-401 cores.

The same report layout is issued under either spec code — only the letterhead
subject line differs. Dispatch picks this parser whenever the PDF text matches
``ame_common.is_cores_report``.

The report contains two column-oriented groups (mat cores, then joint cores).
Each group layout:

    Lot/Sublot TS/SL1 TS /SL2 TS /SL3
    Core ID M1 M2 M3
    Average Core Thickness (as-received), in. 4.70 5.24 4.56
    Average Core Thickness (trimmed), in. 4.20 4.21 4.00
    ASTM D2726, Bulk Specific Gravity 2.434 2.355 2.424
    Theoretical Max. Specific Gravity 2.483 2.483 2.484
    Compaction*, % 98.0 94.9 97.6

A report-wide requirement line appears once:
    *Project Requirements: Mat. >= 94% ; Joint >= 92%

One output row per (sublot, core).
"""

import re

from . import ame_common

EXPECTED_FIELDS = [
    "sublot_number",
    "core_id",
    "core_type",
    "thickness_as_received_in",
    "thickness_trimmed_in",
    "gmb",
    "gmm",
    "compaction_pct",
    "astm_standard",
    "required_compaction_pct",
    "result",
]

# "Lot/Sublot" header line. Old single-lot format: "Lot/Sublot TS/SL1 TS/SL2 TS/SL3".
# New multi-lot format: "Lot/Sublot: 5/6/26 L3/SL3 L4/SL1 L4/SL2 L4/SL3" \u2014 has a colon,
# a leading paving date, and lot-prefixed sublot tokens. Accept both.
SUBLOT_LINE_RE = re.compile(r"^\s*Lot/Sublot:?\s+(.+)$", re.MULTILINE)
# Core ID row may be prefixed with "Mat " or "Joint " on multi-lot reports.
CORE_ID_LINE_RE = re.compile(r"^\s*(?P<kind>Mat|Joint)?\s*Core\s+ID\s+(?P<ids>.+)$", re.MULTILINE)
# Core IDs are always M<n> (mat) or J<n> (joint). Match strictly so placeholder
# cells (".." filler when a 3-column template only has 2 lots of data) don't get
# counted as IDs and trigger a spurious column_count_mismatch.
CORE_ID_TOKEN_RE = re.compile(r"\b[MJ]\d+\b", re.IGNORECASE)
# Sublot label pattern allowing optional whitespace around the slash: "TS/SL1", "L3/SL3", "TS /SL2"
SUBLOT_TOKEN_RE = re.compile(r"[A-Za-z][A-Za-z0-9]*\s*/\s*SL\d+")
THICK_AR_RE = re.compile(r"Average\s+Core\s+Thickness\s*\(as-received\)[^\n]*?\.\s*(.+)")
THICK_TR_RE = re.compile(r"Average\s+Core\s+Thickness\s*\(trimmed\)[^\n]*?\.\s*(.+)")
GMB_RE = re.compile(r"ASTM\s+(D\d+)\s*,\s*Bulk Specific Gravity\s+(.+)")
GMM_RE = re.compile(r"Theoretical\s+Max\.?\s+Specific\s+Gravity\s+(.+)")
COMPACTION_RE = re.compile(r"Compaction\*?,?\s*%\s+(.+)")

# Old P-403 requirements line: "Project Requirements: Mat. >= 94% ; Joint >= 92%".
# New P-401 multi-threshold line: "Project Requirements: Surface Mat \u2265 92.8%; Base Mat \u2265 92.0%; Joint \u2265 90.5%".
# We always use the Surface Mat threshold for mat cores (production cores from a paving lift
# are virtually always the surface course unless labeled otherwise).
REQUIREMENTS_RE = re.compile(
    r"Project\s+Requirements?:\s*"
    r"(?:Surface\s+)?Mat\.?\s*[>\u2265]=?\s*(?P<mat>[\d.]+)\s*%"
    r"[^\n]*?"
    r"Joint\s*[>\u2265]=?\s*(?P<joint>[\d.]+)\s*%",
    re.IGNORECASE,
)

CORE_TYPE_PREFIX = {"M": "mat", "J": "joint"}


def parse(text: str) -> dict:
    header = ame_common.parse_header(text)
    errors = []

    req_mat, req_joint = _parse_requirements(text)
    if req_mat is None or req_joint is None:
        errors.append("missing_compaction_requirements")

    groups = _split_core_groups(text)
    if not groups:
        errors.append("no_core_groups_found")

    rows = []
    for idx, group_text in enumerate(groups):
        group_rows, group_errors = _parse_group(group_text, idx, req_mat, req_joint)
        rows.extend(group_rows)
        errors.extend(group_errors)

    return {"header": header, "rows": rows, "errors": errors}


def _parse_requirements(text: str):
    m = REQUIREMENTS_RE.search(text)
    if not m:
        return None, None
    return ame_common.to_float(m.group("mat")), ame_common.to_float(m.group("joint"))


def _split_core_groups(text: str):
    """Each group starts at a 'Lot/Sublot ...' line and runs to the next one or end."""
    matches = list(SUBLOT_LINE_RE.finditer(text))
    groups = []
    for i, m in enumerate(matches):
        start = m.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        groups.append(text[start:end])
    return groups


def _parse_group(group_text: str, group_index: int, req_mat, req_joint):
    errors = []
    tag = f"@group{group_index + 1}"

    sublots = _extract_sublot_tokens(group_text)
    group_core_type, core_ids = _extract_core_id_tokens(group_text)

    if not sublots or not core_ids:
        errors.append(f"missing_sublot_or_core_id_row{tag}")
        return [], errors

    n = min(len(sublots), len(core_ids))
    if len(sublots) != len(core_ids):
        errors.append(f"column_count_mismatch{tag}")

    thick_ar = _numeric_columns(THICK_AR_RE, group_text, n)
    thick_tr = _numeric_columns(THICK_TR_RE, group_text, n)
    compaction = _numeric_columns(COMPACTION_RE, group_text, n)

    gmb_m = GMB_RE.search(group_text)
    astm = gmb_m.group(1) if gmb_m else None
    gmb_vals = _split_floats(gmb_m.group(2), n) if gmb_m else [None] * n

    gmm_m = GMM_RE.search(group_text)
    gmm_vals = _split_floats(gmm_m.group(1), n) if gmm_m else [None] * n

    rows = []
    for i in range(n):
        core_id = core_ids[i]
        # Prefer the "Mat Core ID" / "Joint Core ID" group header when present
        # (multi-lot reports may have M3 in mat cores AND J3 in joint cores —
        # the per-letter fallback would still work, but the header is authoritative).
        core_type = group_core_type or (CORE_TYPE_PREFIX.get(core_id[:1].upper()) if core_id else None)
        if core_type is None:
            errors.append(f"unknown_core_type:{core_id}{tag}")

        required = req_mat if core_type == "mat" else req_joint if core_type == "joint" else None
        compaction_val = compaction[i] if i < len(compaction) else None
        result = _compute_result(compaction_val, required)

        if thick_ar[i] is None:
            errors.append(f"missing_thickness_as_received:{core_id}{tag}")
        if thick_tr[i] is None:
            errors.append(f"missing_thickness_trimmed:{core_id}{tag}")
        if gmb_vals[i] is None:
            errors.append(f"missing_gmb:{core_id}{tag}")
        if gmm_vals[i] is None:
            errors.append(f"missing_gmm:{core_id}{tag}")
        if compaction_val is None:
            errors.append(f"missing_compaction:{core_id}{tag}")

        rows.append({
            "sublot_number": sublots[i],
            "core_id": core_id,
            "core_type": core_type,
            "thickness_as_received_in": thick_ar[i],
            "thickness_trimmed_in": thick_tr[i],
            "gmb": gmb_vals[i],
            "gmm": gmm_vals[i],
            "compaction_pct": compaction_val,
            "astm_standard": astm,
            "required_compaction_pct": required,
            "result": result,
        })

    return rows, errors


def _extract_sublot_tokens(group_text: str):
    """Pull sublot labels from the 'Lot/Sublot ...' row.

    pdfplumber sometimes emits 'TS/SL1 TS /SL2 TS /SL3' — the space inside 'TS /SLn'
    defeats naive whitespace splitting. Match the full sublot pattern instead and
    strip internal whitespace.
    """
    m = SUBLOT_LINE_RE.search(group_text)
    if not m:
        return []
    return [re.sub(r"\s+", "", tok) for tok in SUBLOT_TOKEN_RE.findall(m.group(1))]


def _extract_core_id_tokens(group_text: str):
    """Returns (core_type, [core_id, ...]). core_type is "mat", "joint", or None
    (None when the row has no explicit kind prefix — caller falls back to first letter)."""
    m = CORE_ID_LINE_RE.search(group_text)
    if not m:
        return None, []
    kind = m.group("kind")
    core_type = {"Mat": "mat", "Joint": "joint"}.get(kind.title()) if kind else None
    return core_type, CORE_ID_TOKEN_RE.findall(m.group("ids"))


def _numeric_columns(pattern: re.Pattern, text: str, n: int):
    m = pattern.search(text)
    if not m:
        return [None] * n
    return _split_floats(m.group(1), n)


def _split_floats(s: str, n: int):
    values = [ame_common.to_float(tok) for tok in s.split()]
    values = [v for v in values if v is not None]
    if len(values) < n:
        values = values + [None] * (n - len(values))
    return values[:n]


def _compute_result(compaction_pct, required_pct):
    if compaction_pct is None or required_pct is None:
        return None
    return "pass" if compaction_pct >= required_pct else "fail"
