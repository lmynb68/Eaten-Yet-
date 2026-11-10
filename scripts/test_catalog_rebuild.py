"""Catalog reconstruction regression tests; every write uses an isolated copy."""

import contextlib
import copy
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "docs"))
import rebuild_catalog as catalog


class CatalogRebuildTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix=".catalog-test-", dir=REPO)
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "docs").mkdir()
        (self.root / "assets").mkdir()
        for name in (*catalog.IMPORT_SCRIPTS, *catalog.SOURCE_FILES):
            shutil.copyfile(REPO / "docs" / name, self.root / "docs" / name)
        self.target = self.root / "assets" / "official.json"
        shutil.copyfile(REPO / "assets" / "official.json", self.target)
        self.original = self.target.read_bytes()
        self.current = json.loads(self.original)

    def rebuild(self, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            return catalog.rebuild(self.root, **kwargs)

    def write_current(self, data):
        self.target.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        return self.target.read_bytes()

    def test_full_rebuild_repeats_without_changing_reviewed_catalog(self):
        first = self.rebuild()
        second = self.rebuild()
        checked = self.rebuild(check_only=True)
        self.assertEqual(first, self.current)
        self.assertEqual(second, first)
        self.assertEqual(checked, first)
        self.assertEqual(first["revision"], 10)
        self.assertEqual(len(first["offers"]), 1735)
        self.assertEqual(sum(row["placeId"] == "mg" for row in first["offers"]), 101)
        self.assertEqual(self.target.read_bytes(), self.original)
        self.assertEqual(sorted(path.name for path in (self.root / "assets").iterdir()), ["official.json"])

    def test_missing_maigang_step_cannot_downgrade_catalog(self):
        scripts = tuple(name for name in catalog.IMPORT_SCRIPTS if name != "import_maigang.py")
        with patch.object(catalog, "IMPORT_SCRIPTS", scripts):
            with self.assertRaisesRegex(catalog.RebuildError, "backwards"):
                self.rebuild()
        self.assertEqual(self.target.read_bytes(), self.original)

    def test_missing_restaurant_is_rejected_even_with_same_revision(self):
        candidate = copy.deepcopy(self.current)
        candidate["places"] = [row for row in candidate["places"] if row["id"] != "mg"]
        candidate["offers"] = [row for row in candidate["offers"] if row["placeId"] != "mg"]
        with patch.object(catalog, "build_candidate", return_value=candidate):
            with self.assertRaisesRegex(catalog.RebuildError, "missing=.*mg"):
                self.rebuild()
        self.assertEqual(self.target.read_bytes(), self.original)

    def test_reviewed_price_change_is_not_overwritten(self):
        self.current["offers"][0]["priceCents"] += 1
        original = self.write_current(self.current)
        with self.assertRaisesRegex(catalog.RebuildError, "changed=.*sf_001"):
            self.rebuild()
        self.assertEqual(self.target.read_bytes(), original)

    def test_added_offer_not_in_reconstruction_is_not_dropped(self):
        extra = copy.deepcopy(self.current["offers"][0])
        extra["id"] = "reviewed-new-offer"
        self.current["offers"].append(extra)
        original = self.write_current(self.current)
        with self.assertRaisesRegex(catalog.RebuildError, "missing=.*reviewed-new-offer"):
            self.rebuild()
        self.assertEqual(self.target.read_bytes(), original)

    def test_incomplete_maigang_source_leaves_original_untouched(self):
        source_path = self.root / "docs" / "catalog-maigang.json"
        source = json.loads(source_path.read_text(encoding="utf-8"))
        source["offers"].pop()
        source_path.write_text(json.dumps(source), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "101 unique offers"):
            self.rebuild()
        self.assertEqual(self.target.read_bytes(), self.original)

    def test_direct_maigang_import_cannot_overwrite_reviewed_price(self):
        offer = next(row for row in self.current["offers"] if row["placeId"] == "mg")
        offer["priceCents"] = 12345
        original = self.write_current(self.current)
        result = subprocess.run(
            [sys.executable, "-X", "utf8", str(self.root / "docs" / "import_maigang.py")],
            cwd=self.root, capture_output=True, text=True, encoding="utf-8", check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("rebuild_catalog.py", result.stderr)
        self.assertEqual(self.target.read_bytes(), original)

    def test_invalid_new_offer_does_not_replace_original(self):
        invalid_fields = (
            ("priceCents", -1), ("priceCents", 0), ("priceCents", True),
            ("name", ""), ("portion", None), ("placeId", "missing-store"),
            ("foodIds", ["missing-food"]), ("available", "true"),
            ("mealPeriods", []), ("kind", "unknown"), ("updatedAt", "invalid"),
        )
        for field, value in invalid_fields:
            with self.subTest(field=field, value=value):
                candidate = copy.deepcopy(self.current)
                candidate["revision"] += 1
                offer = copy.deepcopy(candidate["offers"][0])
                offer.update({"id": "new-offer", field: value})
                candidate["offers"].append(offer)
                with patch.object(catalog, "build_candidate", return_value=candidate):
                    with self.assertRaises(catalog.RebuildError):
                        self.rebuild()
                self.assertEqual(self.target.read_bytes(), self.original)

    def test_invalid_new_restaurant_food_and_rice_plan_are_rejected(self):
        cases = (
            ("places", {"id": "new-store", "name": "", "area": ""}),
            ("foods", {"id": "new-food", "name": ""}),
        )
        for section, entry in cases:
            with self.subTest(section=section):
                candidate = copy.deepcopy(self.current)
                candidate["revision"] += 1
                candidate[section].append(entry)
                with patch.object(catalog, "build_candidate", return_value=candidate):
                    with self.assertRaises(catalog.RebuildError):
                        self.rebuild()
                self.assertEqual(self.target.read_bytes(), self.original)
        for field, value in (("storeKey", "official:missing-store"), ("priceCents", -1), ("labels", [[], [], []])):
            with self.subTest(section="ricePlans", field=field):
                candidate = copy.deepcopy(self.current)
                candidate["revision"] += 1
                plan = copy.deepcopy(candidate["ricePlans"][0])
                plan.update({"id": "new-plan", field: value})
                candidate["ricePlans"].append(plan)
                with patch.object(catalog, "build_candidate", return_value=candidate):
                    with self.assertRaises(catalog.RebuildError):
                        self.rebuild()
                self.assertEqual(self.target.read_bytes(), self.original)

    def test_valid_new_offer_with_new_revision_can_be_written(self):
        candidate = copy.deepcopy(self.current)
        candidate["revision"] += 1
        offer = copy.deepcopy(candidate["offers"][0])
        offer["id"] = "new-offer"
        candidate["offers"].append(offer)
        with patch.object(catalog, "build_candidate", return_value=candidate):
            self.assertEqual(self.rebuild(), candidate)
        self.assertEqual(json.loads(self.target.read_bytes()), candidate)

    def test_check_mode_does_not_apply_new_reviewed_entries(self):
        older = copy.deepcopy(self.current)
        older["revision"] = 9
        older["places"] = [row for row in older["places"] if row["id"] != "mg"]
        older["offers"] = [row for row in older["offers"] if row["placeId"] != "mg"]
        original = self.write_current(older)
        with self.assertRaisesRegex(catalog.RebuildError, "review it before updating"):
            self.rebuild(check_only=True)
        self.assertEqual(self.target.read_bytes(), original)
        self.assertEqual(self.rebuild(), self.current)
        self.assertEqual(json.loads(self.target.read_bytes()), self.current)

    def test_replace_failure_preserves_old_catalog_and_cleans_temp_file(self):
        candidate = copy.deepcopy(self.current)
        candidate["revision"] += 1
        with patch.object(catalog, "build_candidate", return_value=candidate):
            with patch.object(catalog.os, "replace", side_effect=OSError("disk unavailable")):
                with self.assertRaisesRegex(OSError, "disk unavailable"):
                    self.rebuild()
        self.assertEqual(self.target.read_bytes(), self.original)
        self.assertEqual(sorted(path.name for path in (self.root / "assets").iterdir()), ["official.json"])

    def test_concurrent_edit_is_preserved(self):
        candidate = copy.deepcopy(self.current)
        candidate["revision"] += 1
        concurrent = self.original + b"\n"

        def build_with_edit(root):
            self.target.write_bytes(concurrent)
            return candidate

        with patch.object(catalog, "build_candidate", side_effect=build_with_edit):
            with self.assertRaisesRegex(catalog.RebuildError, "changed during reconstruction"):
                self.rebuild()
        self.assertEqual(self.target.read_bytes(), concurrent)


if __name__ == "__main__":
    unittest.main()
