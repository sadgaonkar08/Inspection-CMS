"""ISI — P-610 concrete cylinder break reports.

Each ISI report describes one set of concrete cylinders (typically 5: A-E) taken
from a single pour. The report emits one structured row per report with the
cylinder breaks nested in `data.cylinders`.

Typical layout (abridged):

    Lab ID No.: 94223 Set # 1 of 1
    ISI File No.: 3135-002.0
    Approval Date: 04/20/2026
    Project Name: SFO RWY 1R
    Client Name: ATKINS REALIS
    COMPRESSION TEST REPORT
    Material Type: CONCRETE ... Sampled By: TONY BOSQUE
    Supplier: GRANTEROCK
    Mix No.: 571801    Date/Time Sampled: Mon, 04/13/26 9:00 AM
    Truck No. / Ticket No.: 2420 / 38110031   No. of Samples: 5
    Location in Structure: 1LW2 ...            Slump [in.]: 3.50 (C143)
    Fresh Unit Weight [pcf]:             Air Temp [F]: 54
    Air Content [%]: 1.60                Mix Temp [F]: 72
                     Average  Measured  Ultimate  Corr   Ultimate
    ID AGE Date Tested  Diameter (in)  Area  Load (lbs)  Factor  Stress (psi)  Failure Type
    A  7   04/20/2026   4.00 x 8       12.56   76,680   1.00    6,100          5 - Side Fracture
    B  28  05/11/2026   4.00 x 8       12.56                     1.00
    ...
    RESULTS
    Avg. Ultimate Compressive Strength at 28 days: 4,890 psi  Specified strength: 4,000 psi  PASS
"""

import re

from . import isi_common

EXPECTED_FIELDS = [
    "lab_id_number",
    "set_number",
    "date_sampled",
    "specified_strength_psi",
    "avg_strength_psi",
    "avg_strength_at_days",
    "cylinders",
    "result",
]

LAB_ID_RE = re.compile(r"Lab\s+ID\s+No\.?\s*:\s*(\S+)", re.IGNORECASE)
SET_RE = re.compile(r"Set\s*#?\s*([\d\s]+of[\s\d]+)", re.IGNORECASE)
ISI_FILE_RE = re.compile(r"ISI\s+File\s+No\.?\s*:\s*(\S+)", re.IGNORECASE)
APPROVAL_DATE_RE = re.compile(r"Approval\s+Date\s*:\s*(\d{1,2}/\d{1,2}/\d{2,4})?", re.IGNORECASE)
PROJECT_NAME_RE = re.compile(r"Project\s+Name\s*:\s*(.+?)(?:\s{2,}|$)", re.IGNORECASE | re.MULTILINE)
CLIENT_NAME_RE = re.compile(r"Client\s+Name\s*:\s*(.+?)(?:\s{2,}|$)", re.IGNORECASE | re.MULTILINE)
MATERIAL_RE = re.compile(r"Material\s+Type\s*:\s*(.+?)\s+Sampled\s+By", re.IGNORECASE)
SUPPLIER_RE = re.compile(r"Supplier\s*:\s*(.+?)\s*$", re.IGNORECASE | re.MULTILINE)
MIX_RE = re.compile(r"Mix\s+No\.?\s*:\s*(\S+)", re.IGNORECASE)
DATE_SAMPLED_RE = re.compile(
    r"Date/Time\s+Sampled\s*:\s*(?:\w+,\s*)?(\d{1,2}/\d{1,2}/\d{2,4})",
    re.IGNORECASE,
)
NUM_SAMPLES_RE = re.compile(r"No\.?\s+of\s+Samples\s*:\s*(\d+)", re.IGNORECASE)
SLUMP_RE = re.compile(r"Slump\s*\[in\.?\]\s*:\s*([\d.]+)?", re.IGNORECASE)
AIR_CONTENT_RE = re.compile(r"Air\s+Content\s*\[%\]\s*:\s*([\d.]+)?", re.IGNORECASE)
AIR_TEMP_RE = re.compile(r"Air\s+Temp\s*\[F\]\s*:\s*([\d.]+)?", re.IGNORECASE)
MIX_TEMP_RE = re.compile(r"Mix\s+Temp\s*\[F\]\s*:\s*([\d.]+)?", re.IGNORECASE)

# Captures everything between "Truck No. / Ticket No.:" and "No. of Samples:"
# so we can split on '/' ourselves. The ticket side may legitimately contain "N/R".
TRUCK_TICKET_SEGMENT_RE = re.compile(
    r"Truck\s+No\.?\s*/\s*Ticket\s+No\.?\s*:\s*(?P<seg>.*?)\s+No\.?\s+of\s+Samples",
    re.IGNORECASE | re.DOTALL,
)
TESTED_ROW_RE = re.compile(
    r"^\s*(?P<age>\d+)\s+"
    r"(?P<date>\d{1,2}/\d{1,2}/\d{2,4})\s+"
    r"(?P<dia>[\d.]+)\s*x\s*(?P<len>[\d.]+)\s+"
    r"(?P<area>[\d.,]+)\s+"
    r"(?P<load>[\d.,]+)\s+"
    r"(?P<cf>[\d.]+)\s+"
    r"(?P<stress>[\d.,]+)\s+"
    r"(?P<failure>.+)$"
)
# "Scheduled but not yet tested" row: age + date + dia x len + area + correction factor, blanks for load/stress/failure
SCHEDULED_ROW_RE = re.compile(
    r"^\s*(?P<age>\d+)\s+"
    r"(?P<date>\d{1,2}/\d{1,2}/\d{2,4})\s+"
    r"(?P<dia>[\d.]+)\s*x\s*(?P<len>[\d.]+)\s+"
    r"(?P<area>[\d.,]+)\s+"
    r"(?P<cf>[\d.]+)\s*$"
)
HELD_ROW_RE = re.compile(r"^\s*H\s*$")

RESULTS_RE = re.compile(
    r"Avg\.\s*Ultimate\s*Compressive\s*Strength\s*at\s*(?P<days>\d+)\s*days?\s*:\s*"
    r"(?P<avg>[\d.,]+)?\s*psi\s*"
    r"Specified\s*strength\s*:\s*(?P<spec>[\d.,]+)\s*psi"
    r"(?:\s+(?P<verdict>PASS|FAIL))?",
    re.IGNORECASE,
)


def parse(text: str) -> dict:
    errors = []
    header = _parse_header(text)

    cylinders, cyl_errors = _parse_cylinders(text)
    errors.extend(cyl_errors)

    results = _parse_results_line(text)
    if not results:
        errors.append("missing_results_line")

    reported_avg_psi = results.get("avg_psi") if results else None
    reported_at_days = results.get("days") if results else None
    specified_psi = results.get("specified_psi") if results else None

    if specified_psi is None:
        errors.append("missing_specified_strength")

    avg_psi, avg_at_days, avg_source = _effective_average(
        cylinders, reported_avg_psi, reported_at_days
    )
    result = _compute_verdict(avg_psi, specified_psi, avg_source)

    row = {
        **header,
        "cylinders": cylinders,
        "num_cylinders": len(cylinders),
        "num_tested": sum(1 for c in cylinders if c.get("status") == "tested"),
        "avg_strength_psi": avg_psi,
        "avg_strength_at_days": avg_at_days,
        "avg_strength_source": avg_source,
        "specified_strength_psi": specified_psi,
        "specified_at_days": reported_at_days,
        "result": result,
    }

    return {
        "header": {
            "lab_name": isi_common.LAB_NAME,
            "report_date": header.get("approval_date") or header.get("date_sampled"),
            "project_name": header.get("project_name"),
            "client_name": header.get("client_name"),
            "supplier": header.get("supplier"),
            "mix_number": header.get("mix_number"),
        },
        "rows": [row],
        "errors": errors,
    }


def _parse_header(text: str) -> dict:
    truck, ticket = _truck_and_ticket(text)
    return {
        "lab_id_number": _match(LAB_ID_RE, text),
        "set_number": _clean_set(_match(SET_RE, text)),
        "isi_file_number": _match(ISI_FILE_RE, text),
        "approval_date": isi_common.parse_us_date(_match(APPROVAL_DATE_RE, text)),
        "project_name": _match(PROJECT_NAME_RE, text),
        "client_name": _match(CLIENT_NAME_RE, text),
        "material_type": _match(MATERIAL_RE, text) or "CONCRETE",
        "supplier": _match_not_na(SUPPLIER_RE, text),
        "mix_number": _match_not_na(MIX_RE, text),
        "date_sampled": isi_common.parse_us_date(_match(DATE_SAMPLED_RE, text)),
        "truck_number": truck,
        "ticket_number": ticket,
        "num_samples": isi_common.to_int(_match(NUM_SAMPLES_RE, text)),
        "slump_in": isi_common.to_float(_match(SLUMP_RE, text)),
        "air_content_pct": isi_common.to_float(_match(AIR_CONTENT_RE, text)),
        "air_temp_f": isi_common.to_float(_match(AIR_TEMP_RE, text)),
        "mix_temp_f": isi_common.to_float(_match(MIX_TEMP_RE, text)),
    }


def _parse_cylinders(text: str):
    errors = []
    cylinders = []
    lines = text.splitlines()

    for i, line in enumerate(lines):
        m = re.match(r"^([A-E])\b(.*)$", line)
        if not m:
            continue
        cyl_id = m.group(1)
        rest = m.group(2)

        tested = TESTED_ROW_RE.match(rest)
        if tested:
            cylinders.append({
                "id": cyl_id,
                "status": "tested",
                "age_days": isi_common.to_int(tested.group("age")),
                "date_tested": isi_common.parse_us_date(tested.group("date")),
                "diameter_in": isi_common.to_float(tested.group("dia")),
                "length_in": isi_common.to_float(tested.group("len")),
                "area_sqin": isi_common.to_float(tested.group("area")),
                "ultimate_load_lbs": isi_common.to_float(tested.group("load")),
                "correction_factor": isi_common.to_float(tested.group("cf")),
                "ultimate_stress_psi": isi_common.to_float(tested.group("stress")),
                "failure_type": isi_common.clean(tested.group("failure")),
            })
            continue

        scheduled = SCHEDULED_ROW_RE.match(rest)
        if scheduled:
            cylinders.append({
                "id": cyl_id,
                "status": "scheduled",
                "age_days": isi_common.to_int(scheduled.group("age")),
                "date_tested": isi_common.parse_us_date(scheduled.group("date")),
                "diameter_in": isi_common.to_float(scheduled.group("dia")),
                "length_in": isi_common.to_float(scheduled.group("len")),
                "area_sqin": isi_common.to_float(scheduled.group("area")),
                "correction_factor": isi_common.to_float(scheduled.group("cf")),
                "ultimate_load_lbs": None,
                "ultimate_stress_psi": None,
                "failure_type": None,
            })
            continue

        if HELD_ROW_RE.match(rest):
            cylinders.append({"id": cyl_id, "status": "held"})
            continue

        # Something matched the ID but not any known row shape — flag it.
        if rest.strip():
            errors.append(f"unparsed_cylinder_row:{cyl_id}")

    if not cylinders:
        errors.append("no_cylinders_found")

    return cylinders, errors


def _parse_results_line(text: str):
    m = RESULTS_RE.search(text)
    if not m:
        return None
    return {
        "days": isi_common.to_int(m.group("days")),
        "avg_psi": isi_common.to_float(m.group("avg")),
        "specified_psi": isi_common.to_float(m.group("spec")),
        "verdict": (m.group("verdict") or "").lower() or None,
    }


def _effective_average(cylinders, reported_avg_psi, reported_at_days):
    """Decide what average to use for pass/fail.

    Prefer the Results line (reported by the lab). Otherwise, if any cylinders
    have been tested, average their measured stresses — useful for early-break
    reports (e.g. 7-day) where the 28-day average isn't calculated yet.

    Returns (avg_psi, avg_at_days, source) where source is one of:
      - "report"                          lab-calculated average
      - "computed_from_tested_cylinders"  avg of tested cylinders when lab hasn't filled in the Results line
      - None                              no data available
    """
    if reported_avg_psi is not None:
        return reported_avg_psi, reported_at_days, "report"

    tested = [
        c for c in cylinders
        if c.get("status") == "tested" and c.get("ultimate_stress_psi") is not None
    ]
    if not tested:
        return None, reported_at_days, None

    avg = sum(c["ultimate_stress_psi"] for c in tested) / len(tested)
    ages = [c["age_days"] for c in tested if c.get("age_days") is not None]
    # If cylinders were tested at different ages, use the min (most conservative / earliest).
    age_at_days = min(ages) if ages else None
    return round(avg, 1), age_at_days, "computed_from_tested_cylinders"


def _compute_verdict(avg_psi, specified_psi, avg_source):
    """Derive pass/fail from the effective average.

    - With a lab-reported average, trust it: pass if >= spec, fail otherwise.
    - With an early-break computed average: pass if already >= spec (concrete
      strength only grows with age, so meeting the 28-day spec earlier is a
      definitive pass). Below spec stays pending — the 28-day breaks could
      still push the lot over the threshold.
    """
    if avg_psi is None or specified_psi is None:
        return None
    if avg_psi >= specified_psi:
        return "pass"
    return "fail" if avg_source == "report" else None


def _match(pattern: re.Pattern, text: str):
    m = pattern.search(text)
    return isi_common.clean(m.group(1)) if m and m.group(1) else None


def _match_not_na(pattern: re.Pattern, text: str):
    v = _match(pattern, text)
    return None if v and v.upper() in {"N/A", "N/R"} else v


def _clean_set(s):
    if not s:
        return None
    return re.sub(r"\s+", " ", s).strip()


def _truck_and_ticket(text: str):
    m = TRUCK_TICKET_SEGMENT_RE.search(text)
    if not m:
        return None, None
    seg = (m.group("seg") or "").strip()
    if not seg or "/" not in seg:
        return None, None
    left, _, right = seg.partition("/")
    return _na(left), _na(right)


def _na(value: str):
    if value is None:
        return None
    v = value.strip()
    if not v or v.upper() in {"N/A", "N/R"}:
        return None
    return v
