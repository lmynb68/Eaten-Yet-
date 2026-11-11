"""Integration checks against the real Dart decoder; requires DART or Dart on PATH."""

import copy
import json
import unittest
from unittest.mock import patch

from test_catalog_rebuild import CatalogFixture, catalog


class CatalogDecoderIntegrationTests(CatalogFixture):
    def test_reviewed_catalog_rebuild_passes_application_round_trip(self):
        result = self.rebuild(check_only=True)
        self.assertEqual(result["revision"], 10)
        self.assertEqual(len(result["offers"]), 1735)
        self.assertEqual(sum(row["placeId"] == "mg" for row in result["offers"]), 101)
        self.assertEqual(self.target.read_bytes(), self.original)

    def test_invalid_photo_and_rice_classification_fail_real_decoder(self):
        for section, field, value in (
            ("offers", "photo", "****"),
            ("ricePlans", "dishTypes", {"test": "fish"}),
        ):
            with self.subTest(section=section):
                candidate = copy.deepcopy(self.current)
                candidate["revision"] += 1
                entry = copy.deepcopy(candidate[section][0])
                entry.update({"id": "invalid-added-entry", field: value})
                candidate[section].append(entry)
                invalid = self.root / "invalid.json"
                invalid.write_text(json.dumps(candidate, ensure_ascii=False), encoding="utf-8")
                with self.assertRaisesRegex(catalog.RebuildError, "decoder rejected candidate"):
                    catalog.validate_with_app(invalid)
                # Even if Python's validation drifts, the actual decoder is a
                # mandatory final gate and the reviewed file stays untouched.
                with patch.object(catalog, "build_candidate", return_value=candidate), patch.object(catalog, "_validate_entries"):
                    with self.assertRaisesRegex(catalog.RebuildError, "decoder rejected candidate"):
                        self.rebuild()
                self.assertEqual(self.target.read_bytes(), self.original)

    def test_saved_serialization_must_fit_application_import_limit(self):
        candidate = copy.deepcopy(self.current)
        candidate["revision"] += 1
        offer = copy.deepcopy(candidate["offers"][0])
        offer.update({"id": "large-added-offer", "notes": "a" * 12000000})
        candidate["offers"].append(offer)
        with patch.object(catalog, "build_candidate", return_value=candidate):
            with self.assertRaisesRegex(catalog.RebuildError, "decoder rejected candidate"):
                self.rebuild()
        self.assertEqual(self.target.read_bytes(), self.original)

    def test_valid_added_offer_is_readable_after_write(self):
        candidate = copy.deepcopy(self.current)
        candidate["revision"] += 1
        offer = copy.deepcopy(candidate["offers"][0])
        offer["id"] = "valid-added-offer"
        candidate["offers"].append(offer)
        with patch.object(catalog, "build_candidate", return_value=candidate):
            self.rebuild()
        catalog.validate_with_app(self.target)
        self.assertEqual(json.loads(self.target.read_bytes()), candidate)


if __name__ == "__main__":
    unittest.main()
