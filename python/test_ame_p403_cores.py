#!/usr/bin/env python3
"""Tests for the AME P-401/P-403 cores parser.

Run with: python -m unittest python.test_ame_p403_cores
       or: cd python && python -m unittest test_ame_p403_cores
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))

from parsers import ame_p403_cores


# 3-column PDF template with only 2 lots of data; empty third column is filled
# with ".." placeholder cells. Regression case for joint-table J2 being dropped
# from the saved results because the placeholder triggered a column_count_mismatch.
PDF_WITH_DOT_PLACEHOLDERS = """\
May 6, 2026
Mr. Nate Smith Project Number 1260185T
AtkinsRéalis USA Inc.
Subject: Runway 1R-19L and Taxiway W Rehabilitation, San Francisco International Airport
Production Cores P-401 Test Results, Granite – Santa Clara Plant
As requested, Applied Materials & Engineering, Inc. (AME) has completed testing P-401 core samples
for Mix No. 15347.
Lot/Sublot: 5/5/26 L3/SL1 L3/SL2 ..
Mat Core ID M1 M2 ..
Average Core Thickness (as-received), in. 7.26 8.30 ..
Average Core Thickness (trimmed), in. 4.02 3.99 ..
ASTM D2726, Bulk Specific Gravity 2.374 2.355 ..
Theoretical Max. Specific Gravity 2.455 2.458 ..
Compaction*, % 96.7 95.8 ..
Lot/Sublot: 5/5/26 L3/SL2 L1/SL2 ..
Joint Core ID J1 J2 ..
Average Core Thickness (as-received), in. 4.71 4.71 ..
Average Core Thickness (trimmed), in. 4.00 4.04 ..
ASTM D2726, Bulk Specific Gravity 2.258 2.287 ..
Theoretical Max. Specific Gravity 2.455 2.458 ..
Compaction*, % 92.0 93.0 ..
*Project Requirements: Surface Mat ≥ 92.8%; Base Mat ≥ 92.0%; Joint ≥ 90.5%
"""


# Fully-populated 4-column multi-lot report. Sanity check that the strict
# core-ID regex doesn't regress the common case.
PDF_FULL_FOUR_COLUMN = """\
May 7, 2026
Mr. Nate Smith Project Number 1260185T
AtkinsRéalis USA Inc.
Subject: Runway 1R-19L and Taxiway W Rehabilitation, San Francisco International Airport
Production Cores P-401 Test Results, Granite – Santa Clara Plant
As requested, Applied Materials & Engineering, Inc. (AME) has completed testing P-401 core samples
for Mix No. 15347.
Lot/Sublot: 5/6/26 L3/SL3 L4/SL1 L4/SL2 L4/SL3
Mat Core ID M3 M1 M2 M3
Average Core Thickness (as-received), in. 9.56 3.72 3.88 7.78
Average Core Thickness (trimmed), in. 4.05 3.63 3.82 4.12
ASTM D2726, Bulk Specific Gravity 2.328 2.337 2.307 2.382
Theoretical Max. Specific Gravity 2.452 2.452 2.454 2.459
Compaction*, % 94.9 95.3 94.0 96.9
Lot/Sublot: 5/6/26 L3/SL3 L4/SL1 L4/SL2 L4/SL3
Joint Core ID J3 J1 J2 J3
Average Core Thickness (as-received), in. 8.25 4.26 4.29 8.12
Average Core Thickness (trimmed), in. 4.02 4.15 4.20 4.13
ASTM D2726, Bulk Specific Gravity 2.350 2.309 2.283 2.306
Theoretical Max. Specific Gravity 2.452 2.452 2.454 2.459
Compaction*, % 95.8 94.2 93.0 93.8
*Project Requirements: Surface Mat ≥ 92.8%; Base Mat ≥ 92.0%; Joint ≥ 90.5%
"""


class TestAmeP403Cores(unittest.TestCase):
    def test_dot_placeholders_do_not_block_extraction(self):
        result = ame_p403_cores.parse(PDF_WITH_DOT_PLACEHOLDERS)

        self.assertEqual(result["errors"], [],
                         "placeholder '..' cells should not produce extraction errors")
        self.assertEqual(len(result["rows"]), 4)

        rows_by_core = {r["core_id"]: r for r in result["rows"]}
        self.assertIn("J2", rows_by_core, "J2 must be extracted from the joint table")

        j2 = rows_by_core["J2"]
        self.assertEqual(j2["sublot_number"], "L1/SL2")
        self.assertEqual(j2["core_type"], "joint")
        self.assertEqual(j2["compaction_pct"], 93.0)
        self.assertEqual(j2["result"], "pass")

    def test_four_column_multi_lot_report(self):
        result = ame_p403_cores.parse(PDF_FULL_FOUR_COLUMN)

        self.assertEqual(result["errors"], [])
        self.assertEqual(len(result["rows"]), 8)

        mat_ids = [r["core_id"] for r in result["rows"] if r["core_type"] == "mat"]
        joint_ids = [r["core_id"] for r in result["rows"] if r["core_type"] == "joint"]
        self.assertEqual(mat_ids, ["M3", "M1", "M2", "M3"])
        self.assertEqual(joint_ids, ["J3", "J1", "J2", "J3"])


if __name__ == "__main__":
    unittest.main()
