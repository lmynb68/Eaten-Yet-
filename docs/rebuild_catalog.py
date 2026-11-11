"""Rebuild reviewed menus in isolation, refusing loss of current menu data.

Run ``python docs/rebuild_catalog.py --check`` to verify reproducibility without
writing. Restaurant import scripts are maintenance inputs, not release actions.
"""

import argparse
import base64
import binascii
from datetime import datetime
import json
import os
from pathlib import Path
import runpy
import re
import shutil
import subprocess
import tempfile
from urllib.parse import unquote


IMPORT_SCRIPTS = (
    "import_wenying.py",
    "import_baite.py",
    "import_baite_chinese.py",
    "import_zhongxiaobei.py",
    "import_fengwei.py",
    "classify_meal_periods.py",
    # This reviewed source includes its own breakfast/lunch/dinner categories.
    "import_maigang.py",
)
SOURCE_FILES = ("catalog-before-wenying.json", "catalog-maigang.json")
COLLECTIONS = ("places", "foods", "offers", "ricePlans")


class RebuildError(ValueError):
    """The candidate cannot safely replace the current catalog."""


def _index(catalog, section):
    rows = catalog.get(section)
    if not isinstance(rows, list):
        raise RebuildError(f"Missing catalog collection: {section}")
    result = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("id"), str):
            raise RebuildError(f"Invalid entry in {section}")
        key = row["id"]
        if not key.strip() or key in result:
            raise RebuildError(f"Empty or duplicate id in {section}: {key}")
        result[key] = row
    return result


def _text(row, key, *, allow_empty=False, default=None):
    value = row.get(key, default)
    if not isinstance(value, str) or (not allow_empty and not value.strip()):
        raise RebuildError(f"Invalid {key} in entry {row.get('id', '?')}")
    return value


def _strings(row, key, *, default=None):
    value = row.get(key, default)
    if not isinstance(value, list) or any(not isinstance(v, str) or not v.strip() for v in value):
        raise RebuildError(f"Invalid {key} in entry {row.get('id', '?')}")
    if len(set(value)) != len(value):
        raise RebuildError(f"Duplicate {key} in entry {row.get('id', '?')}")
    return value


def _price(value, entry_id):
    if type(value) is not int or not 0 < value <= 10000000:
        raise RebuildError(f"Invalid price in entry {entry_id}")


def _photo(row):
    value = _text(row, "photo", allow_empty=True, default="")
    if len(value) > 400000:
        raise RebuildError(f"Photo too large in entry {row['id']}")
    try:
        # Dart accepts URL-safe, unpadded and percent-encoded Base64 as well.
        normalized = unquote(value, encoding="ascii", errors="strict")
        decoded = base64.b64decode(normalized + "=" * (-len(normalized) % 4), altchars=b"-_", validate=True)
    except (ValueError, UnicodeError, binascii.Error) as error:
        raise RebuildError(f"Invalid Base64 photo in entry {row['id']}") from error
    if len(decoded) > 300000:
        raise RebuildError(f"Photo too large in entry {row['id']}")
    return len(value)


def _validate_entries(candidate):
    """Basic types and associations must also hold for newly added records."""
    if type(candidate.get("schemaVersion")) is not int or candidate["schemaVersion"] not in (1, 2, 3, 4):
        raise RebuildError("Unsupported catalog schema")
    if candidate["revision"] < 1:
        raise RebuildError("Invalid catalog revision")
    indexes = {name: _index(candidate, name) for name in COLLECTIONS}
    for name, limit in (("places", 200), ("foods", 2000), ("offers", 2000), ("ricePlans", 100)):
        if len(indexes[name]) > limit:
            raise RebuildError(f"Catalog exceeds {name} capacity")
    photo_size = 0
    for place in indexes["places"].values():
        _text(place, "name")
        _text(place, "area", allow_empty=True)
        photo_size += _photo(place)
    for food in indexes["foods"].values():
        _text(food, "name")
    for offer in indexes["offers"].values():
        for key in ("name", "portion", "placeId", "updatedAt"):
            _text(offer, key)
        for key in ("window", "notes", "evidence", "observedAt", "photo", "staple"):
            _text(offer, key, allow_empty=True, default="")
        photo_size += _photo(offer)
        _price(offer.get("priceCents"), offer["id"])
        if offer["placeId"] not in indexes["places"]:
            raise RebuildError(f"Missing restaurant for offer {offer['id']}")
        food_ids = _strings(offer, "foodIds")
        if not set(food_ids).issubset(indexes["foods"]):
            raise RebuildError(f"Missing food association for offer {offer['id']}")
        for key in ("available", "ingredientsKnown", "example", "addonOnly", "alcohol"):
            default = False if key in ("addonOnly", "alcohol") else None
            if type(offer.get(key, default)) is not bool:
                raise RebuildError(f"Invalid {key} in offer {offer['id']}")
        periods = _strings(offer, "mealPeriods", default=["breakfast", "lunch", "dinner"])
        roles = _strings(offer, "roles")
        kind = offer.get("kind", "dish")
        if (not periods or not set(periods).issubset({"breakfast", "lunch", "dinner"}) or
                not set(roles).issubset({"staple", "protein", "vegetable"}) or
                kind not in ("main", "side", "drink", "dish", "fee") or
                offer.get("channel", "regular") not in ("regular", "douyin") or
                offer.get("staple", "") not in ("", "rice", "noodles", "dumplings", "other", "none") or
                (offer.get("alcohol", False) and kind != "drink") or
                (offer.get("addonOnly", False) and kind != "side") or
                (offer["ingredientsKnown"] and not food_ids)):
            raise RebuildError(f"Invalid categories in offer {offer['id']}")
        try:
            datetime.fromisoformat(offer["updatedAt"])
        except ValueError as error:
            raise RebuildError(f"Invalid date in offer {offer['id']}") from error
    if photo_size > 10000000:
        raise RebuildError("Catalog photos exceed total capacity")
    for plan in indexes["ricePlans"].values():
        for key in ("name", "location"):
            _text(plan, key)
        _price(plan.get("priceCents"), plan["id"])
        store = _text(plan, "storeKey", allow_empty=True, default="")
        if store and store not in {f"official:{key}" for key in indexes["places"]}:
            raise RebuildError(f"Missing restaurant for rice plan {plan['id']}")
        # Several valid plans share the same label for all three groups.
        labels = plan.get("labels")
        options = plan.get("options")
        if (not isinstance(labels, list) or len(labels) != 3 or
                any(not isinstance(label, str) or not label.strip() for label in labels) or
                not isinstance(options, list) or len(options) != 3):
            raise RebuildError(f"Invalid rice groups in plan {plan['id']}")
        for group in options:
            values = _strings({"id": plan["id"], "group": group}, "group")
            if len(values) > 100:
                raise RebuildError(f"Too many rice options in plan {plan['id']}")
        prices = plan.get("dishPrices", {})
        if not isinstance(prices, dict):
            raise RebuildError(f"Invalid dish prices in plan {plan['id']}")
        for name, value in prices.items():
            if not isinstance(name, str) or not name.strip():
                raise RebuildError(f"Invalid dish name in plan {plan['id']}")
            _price(value, plan["id"])
        if prices and any(name not in prices for group in options for name in group):
            raise RebuildError(f"Missing dish price in plan {plan['id']}")
        for key in ("dishTypes", "dishPhotos"):
            values = plan.get(key, {})
            if not isinstance(values, dict) or any(not isinstance(value, str) for value in values.values()):
                raise RebuildError(f"Invalid {key} in plan {plan['id']}")
        if any(value not in ("veg", "meat") for value in plan.get("dishTypes", {}).values()):
            raise RebuildError(f"Invalid dishTypes in plan {plan['id']}")
        if any(not re.fullmatch(r"assets/rice/dish_[0-9]{2}\.webp", value) for value in plan.get("dishPhotos", {}).values()):
            raise RebuildError(f"Invalid dishPhotos in plan {plan['id']}")


def dart_executable(explicit=None):
    executable = explicit or os.environ.get("DART")
    if not executable and os.environ.get("FLUTTER_ROOT"):
        executable = str(Path(os.environ["FLUTTER_ROOT"]) / "bin" / "cache" / "dart-sdk" / "bin" / ("dart.exe" if os.name == "nt" else "dart"))
    if not executable:
        executable = shutil.which("dart")
    if executable and Path(executable).suffix.lower() in (".bat", ".cmd"):
        # Avoid invoking the Flutter batch wrapper through another shell.
        native = Path(executable).parent / "cache" / "dart-sdk" / "bin" / "dart.exe"
        if native.is_file():
            executable = str(native)
    if not executable:
        raise RebuildError("Dart is required for application validation; pass --dart or set DART/FLUTTER_ROOT")
    return executable


def validate_with_app(path, *, dart=None):
    """Validate the exact staged bytes with the application's own decoder."""
    validator = Path(__file__).resolve().parents[1] / "scripts" / "validate_catalog.dart"
    try:
        result = subprocess.run(
            [dart_executable(dart), str(validator), str(path)],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RebuildError(f"Application catalog validation could not run: {error}") from error
    detail = (result.stderr or result.stdout).strip()[:1000]
    if result.returncode == 1 and result.stderr.startswith("Application decoder FAIL:"):
        raise RebuildError(f"Application catalog decoder rejected candidate (exit {result.returncode}): {detail}")
    if result.returncode != 0 or not result.stdout.startswith("Application decoder PASS:"):
        raise RebuildError(f"Application catalog validation could not complete (exit {result.returncode}): {detail}")


def validate_candidate(current, candidate):
    """Never silently discard revisions, existing rows, or reviewed row edits."""
    if candidate.get("source") != "official" or current.get("source") != "official":
        raise RebuildError("Only official catalogs can be rebuilt")
    for key in current.keys() | candidate.keys():
        if key not in (*COLLECTIONS, "revision") and current.get(key) != candidate.get(key):
            raise RebuildError(f"Catalog metadata changed: {key}; review the reconstruction inputs")
    if type(current.get("revision")) is not int or type(candidate.get("revision")) is not int:
        raise RebuildError("Catalog revision must be an integer")
    if candidate["revision"] < current["revision"]:
        raise RebuildError("Catalog revision would go backwards")
    added_count = 0
    for section in COLLECTIONS:
        before = _index(current, section)
        after = _index(candidate, section)
        removed = sorted(before.keys() - after.keys())
        changed = sorted(key for key in before.keys() & after.keys() if before[key] != after[key])
        if removed or changed:
            raise RebuildError(
                f"Rebuild differs from reviewed {section}: "
                f"missing={removed[:8]}, changed={changed[:8]}. "
                "Reconcile the source data before replacing the catalog."
            )
        added_count += len(after.keys() - before.keys())
    if added_count and candidate["revision"] <= current["revision"]:
        raise RebuildError("New catalog entries require a newer menu revision")
    _validate_entries(candidate)


def build_candidate(root):
    """Run legacy importers only against disposable copies of their inputs."""
    with tempfile.TemporaryDirectory(prefix=".catalog-", dir=root) as directory:
        stage = Path(directory)
        (stage / "docs").mkdir()
        (stage / "assets").mkdir()
        for name in (*IMPORT_SCRIPTS, *SOURCE_FILES):
            shutil.copyfile(root / "docs" / name, stage / "docs" / name)
        for name in IMPORT_SCRIPTS:
            if name == "import_maigang.py":
                module = runpy.run_path(str(stage / "docs" / name))
                target = stage / "assets" / "official.json"
                catalog = json.loads(target.read_text(encoding="utf-8"))
                source = json.loads((stage / "docs" / "catalog-maigang.json").read_text(encoding="utf-8"))
                target.write_text(json.dumps(module["apply_maigang"](catalog, source), ensure_ascii=False), encoding="utf-8")
            else:
                runpy.run_path(str(stage / "docs" / name), run_name="__main__")
        return json.loads((stage / "assets" / "official.json").read_text(encoding="utf-8"))


def rebuild(root, *, check_only=False, dart=None):
    root = Path(root).resolve()
    target = root / "assets" / "official.json"
    original = target.read_bytes()
    current = json.loads(original)
    candidate = build_candidate(root)
    validate_candidate(current, candidate)
    # Equal content keeps its existing bytes; changed content uses the exact
    # serialization which will be installed, including the decoder size limit.
    data = original if candidate == current else (json.dumps(candidate, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".official-", suffix=".json", dir=target.parent, delete=False) as file:
            temporary = Path(file.name)
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
        validate_with_app(temporary, dart=dart)
        # An editor/importer may have changed the reviewed catalog while we ran.
        if target.read_bytes() != original:
            raise RebuildError("official.json changed during reconstruction; retry after review")
        if check_only and candidate != current:
            raise RebuildError("Reconstruction differs from official.json; review it before updating")
        if check_only or candidate == current:
            return candidate
        os.replace(temporary, target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return candidate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check only; never write official.json")
    parser.add_argument("--dart", help="Dart executable path (otherwise DART, FLUTTER_ROOT, or PATH)")
    args = parser.parse_args()
    try:
        result = rebuild(Path(__file__).resolve().parents[1], check_only=args.check, dart=args.dart)
    except (ValueError, OSError) as error:
        parser.exit(1, f"Catalog rebuild stopped; original file preserved: {error}\n")
    print(f"Catalog verified: revision {result['revision']}, {len(result['places'])} restaurants, {len(result['offers'])} offers")


if __name__ == "__main__":
    main()
