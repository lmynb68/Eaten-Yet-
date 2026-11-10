"""Apply the reviewed November 4 Maigang source after meal classification."""

import copy


def apply_maigang(catalog, source):
    place = source["place"]
    offers = source["offers"]
    ids = [offer["id"] for offer in offers]
    if place["id"] != "mg" or len(offers) != 101 or len(set(ids)) != 101:
        raise ValueError("The reviewed Maigang source must contain its 101 unique offers")
    if any(offer.get("placeId") != "mg" for offer in offers):
        raise ValueError("Maigang source contains another restaurant's offer")
    db = copy.deepcopy(catalog)
    other_ids = {offer["id"] for offer in db["offers"] if offer["placeId"] != "mg"}
    if other_ids.intersection(ids):
        raise ValueError("Maigang offer IDs conflict with another restaurant")
    db["places"] = [row for row in db["places"] if row["id"] != "mg"] + [copy.deepcopy(place)]
    db["offers"] = [row for row in db["offers"] if row["placeId"] != "mg"] + copy.deepcopy(offers)
    db["revision"] = max(db["revision"], source["revision"])
    return db


if __name__ == "__main__":
    raise SystemExit("Run docs/rebuild_catalog.py instead; this importer only transforms in-memory data.")
